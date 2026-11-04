import 'dart:math' as math;

import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/prepared_curve.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Reuses the stable prefix of a live curve. Corrections, removed series and
/// changed first-drip markers rebuild the affected state instead of assuming
/// that every device update is an append.
class CurveAccumulator {
  ShotCurve? _previous;
  ShotCurve? _shown;
  int? _firstDrip;
  final _samples = <CurveSeries, _Values>{};
  _Values _distribution = _Values();
  double _integral = 0;
  int? _start;
  int? _end;
  double _low = double.infinity;
  double _high = double.negativeInfinity;
  bool _valid = true;
  int smoothedSamples = 0;
  int integratedSegments = 0;

  PreparedCurve prepare(CurveRequest request) {
    final curve = request.curve;
    final old = _previous;
    var append =
        old != null &&
        curve.timesMs.length >= old.timesMs.length &&
        request.firstDripMs == _firstDrip;
    if (append) {
      for (final series in CurveSeries.values) {
        if (old.values(series).isEmpty != curve.values(series).isEmpty) {
          append = false;
        }
      }
      for (var i = 0; append && i < old.timesMs.length; i++) {
        if (old.timesMs[i] != curve.timesMs[i]) {
          append = false;
          break;
        }
        for (final series in curve.series) {
          if (old.values(series)[i] != curve.values(series)[i]) {
            append = false;
            break;
          }
        }
      }
    }
    final before = append ? old!.timesMs.length : 0;
    if (!append) {
      _samples.clear();
      _distribution = _Values();
      _integral = 0;
      _start = _end = null;
      _low = double.infinity;
      _high = double.negativeInfinity;
      _valid = true;
    }
    for (var i = before; i < curve.timesMs.length; i++) {
      if (curve.timesMs[i] < 0 ||
          (i > 0 && curve.timesMs[i] <= curve.timesMs[i - 1])) {
        _valid = false;
      }
      for (final series in curve.series) {
        final value = curve.values(series)[i];
        if (!value.isFinite) {
          if (series != CurveSeries.pressure) _valid = false;
          continue;
        }
        (_samples[series] ??= _Values()).add(value, count: 1);
      }
    }
    // The fallback crossing is final once observed. Until then only the new
    // weight segments need inspection; a later explicit marker resets above.
    if (_valid && _start == null && curve.timesMs.isNotEmpty) {
      if (request.firstDripMs case final first? when first >= 0) {
        _start = math.max(curve.timesMs.first, first);
      } else if (curve.weight.isNotEmpty) {
        for (var i = math.max(0, before - 1); i < curve.weight.length; i++) {
          if (curve.weight[i] < .1) continue;
          _start = i == 0
              ? curve.timesMs.first
              : (curve.timesMs[i - 1] +
                        (.1 - curve.weight[i - 1]) /
                            (curve.weight[i] - curve.weight[i - 1]) *
                            (curve.timesMs[i] - curve.timesMs[i - 1]))
                    .ceil();
          break;
        }
      }
    }
    if (_valid && _start != null && curve.flow.isNotEmpty) {
      for (var i = math.max(1, before); i < curve.timesMs.length; i++) {
        final right = curve.timesMs[i];
        if (right <= _start!) continue;
        final left = math.max(curve.timesMs[i - 1], _start!);
        final b = curve.flow[i];
        final originalA = curve.flow[i - 1];
        final a =
            originalA +
            (b - originalA) *
                (left - curve.timesMs[i - 1]) /
                (right - curve.timesMs[i - 1]);
        final duration = right - left;
        _integral += (a + b) / 2 * duration;
        final low = math.min(a, b);
        final high = math.max(a, b);
        _low = math.min(_low, low);
        _high = math.max(_high, high);
        // Nearly flat segments would create enormous cancelling slopes.
        // A midpoint mass changes a quantile by at most 5e-10 flow units;
        // recorded values, mean and maximum remain untouched.
        if (high - low <= 1e-9) {
          _distribution.add((low + high) / 2, offset: duration.toDouble());
        } else {
          final slope = duration / (high - low);
          _distribution.add(low, slope: slope, offset: -low * slope);
          _distribution.add(high, slope: -slope, offset: high * slope);
        }
        _end = right;
        integratedSegments++;
      }
    }
    final shown = _smooth(curve, append ? before : 0);
    _previous = curve;
    _shown = shown;
    _firstDrip = request.firstDripMs;
    return PreparedCurve(
      recorded: curve,
      shown: shown,
      display: displayCurve(shown),
      peaks: {
        for (final series in curve.series)
          series:
              _samples[series]?.peak(robust: series != CurveSeries.pressure) ??
              0,
      },
      flowStats: _stats(),
    );
  }

  CurveFlowStats? _stats() {
    if (!_valid || _start == null || _end == null || _end! <= _start!) {
      return null;
    }
    final duration = _end! - _start!;
    double quantile(bool upper) {
      var low = _low;
      var high = _high;
      for (var i = 0; i < 48; i++) {
        final mid = (low + high) / 2;
        var elapsed = _distribution.below(mid);
        // Cancellation of segment slopes must not turn an exact half-time
        // plateau into one of its two endpoints.
        if ((elapsed - duration / 2).abs() < duration * 1e-12) {
          elapsed = duration / 2;
        }
        if (upper ? elapsed <= duration / 2 : elapsed < duration / 2) {
          low = mid;
        } else {
          high = mid;
        }
      }
      return (low + high) / 2;
    }

    return CurveFlowStats(
      startMs: _start!,
      endMs: _end!,
      mean: _integral / duration,
      median: (quantile(false) + quantile(true)) / 2,
      max: _high,
    );
  }

  ShotCurve _smooth(ShotCurve curve, int before) {
    if (before == 0 || before < 3 || _shown == null) {
      smoothedSamples += curve.timesMs.length;
      return curve.smoothed();
    }
    if (before == curve.timesMs.length) return _shown!;
    int lowerBound(int time) {
      var low = 0;
      var high = curve.timesMs.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (curve.timesMs[mid] < time) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }

    final start = lowerBound(curve.timesMs[before] - 1200);
    final input = lowerBound(curve.timesMs[start] - 1200);
    List<double> tail(List<double> values) =>
        values.isEmpty ? const [] : values.sublist(input);
    final tailCurve = ShotCurve(
      timesMs: curve.timesMs.sublist(input),
      pressure: tail(curve.pressure),
      flow: tail(curve.flow),
      weight: tail(curve.weight),
    ).smoothed();
    smoothedSamples += tailCurve.timesMs.length;
    List<double> join(CurveSeries series) => curve.values(series).isEmpty
        ? const []
        : [
            ..._shown!.values(series).take(start),
            ...tailCurve.values(series).skip(start - input),
          ];
    return ShotCurve(
      timesMs: curve.timesMs,
      pressure: join(CurveSeries.pressure),
      flow: join(CurveSeries.flow),
      weight: join(CurveSeries.weight),
    );
  }
}

/// AVL tree of flow distribution events and/or ranked sample values. Prefix
/// sums evaluate the elapsed-time CDF without rescanning historical segments.
class _Values {
  _Node? root;
  void add(double key, {int count = 0, double slope = 0, double offset = 0}) =>
      root = _insert(root, key, count, slope, offset);
  double below(double key) {
    var node = root;
    var slope = 0.0;
    var offset = 0.0;
    while (node != null) {
      if (key < node.key) {
        node = node.left;
      } else {
        slope += (node.left?.sumSlope ?? 0) + node.slope;
        offset += (node.left?.sumOffset ?? 0) + node.offset;
        node = node.right;
      }
    }
    return slope * key + offset;
  }

  int countThrough(double key) {
    var node = root;
    var count = 0;
    while (node != null) {
      if (key < node.key) {
        node = node.left;
      } else {
        count += (node.left?.total ?? 0) + node.count;
        node = node.right;
      }
    }
    return count;
  }

  double at(int rank) {
    var node = root!;
    while (true) {
      final left = node.left?.total ?? 0;
      if (rank < left) {
        node = node.left!;
      } else if (rank < left + node.count) {
        return node.key;
      } else {
        rank -= left + node.count;
        node = node.right!;
      }
    }
  }

  double peak({required bool robust}) {
    final n = root?.total ?? 0;
    if (n == 0) return 0;
    if (!robust || n < 20) return math.max(0, at(n - 1));
    final p99 = at(((n - 1) * .99).floor());
    final above = n - countThrough(p99 > 0 ? 2 * p99 : 0);
    return math.max(
      0,
      at(above == 0 || above > math.max(1, n ~/ 100) ? n - 1 : n - 1 - above),
    );
  }

  static _Node _insert(
    _Node? node,
    double key,
    int count,
    double slope,
    double offset,
  ) {
    if (node == null) return _Node(key, count, slope, offset);
    if (key < node.key) {
      node.left = _insert(node.left, key, count, slope, offset);
    } else if (key > node.key) {
      node.right = _insert(node.right, key, count, slope, offset);
    } else {
      node.count += count;
      node.slope += slope;
      node.offset += offset;
    }
    node.refresh();
    final balance = (node.left?.height ?? 0) - (node.right?.height ?? 0);
    if (balance > 1) {
      if (key > node.left!.key) node.left = _left(node.left!);
      return _right(node);
    }
    if (balance < -1) {
      if (key < node.right!.key) node.right = _right(node.right!);
      return _left(node);
    }
    return node;
  }

  static _Node _left(_Node node) {
    final top = node.right!;
    node.right = top.left;
    top.left = node;
    node.refresh();
    top.refresh();
    return top;
  }

  static _Node _right(_Node node) {
    final top = node.left!;
    node.left = top.right;
    top.right = node;
    node.refresh();
    top.refresh();
    return top;
  }
}

class _Node {
  _Node(this.key, this.count, this.slope, this.offset) {
    refresh();
  }
  final double key;
  int count;
  int total = 0;
  int height = 1;
  double slope;
  double offset;
  double sumSlope = 0;
  double sumOffset = 0;
  _Node? left;
  _Node? right;
  void refresh() {
    height = 1 + math.max(left?.height ?? 0, right?.height ?? 0);
    total = count + (left?.total ?? 0) + (right?.total ?? 0);
    sumSlope = slope + (left?.sumSlope ?? 0) + (right?.sumSlope ?? 0);
    sumOffset = offset + (left?.sumOffset ?? 0) + (right?.sumOffset ?? 0);
  }
}
