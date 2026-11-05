import 'dart:math' as math;

import 'package:holybeans/domain/shot_curve.dart';

typedef GuidePoint = ({int elapsedMs, double value, bool breakBefore});

/// Gravimetric flow on the extraction clock, using the same trailing weight
/// window for a saved reference and a live scale. Device flow units are ignored.
class FlowTrace {
  static const staleAfter = Duration(seconds: 2);
  static const windowMs = 1000;
  static const warmupMs = 500;
  final _window = <({int ms, double grams})>[];
  final _points = <GuidePoint>[];
  List<GuidePoint>? _snapshot;
  bool _breakNext = true;
  double? current;

  List<GuidePoint> get points => _snapshot ??= List.unmodifiable(_points);

  void breakSegment() {
    _window.clear();
    current = null;
    _breakNext = true;
  }

  void clear() {
    breakSegment();
    _points.clear();
    _snapshot = null;
  }

  void add(int elapsedMs, double grams) {
    if (elapsedMs < 0 || !grams.isFinite || grams < -0.3) {
      breakSegment();
      return;
    }
    if (_points.isNotEmpty && elapsedMs <= _points.last.elapsedMs) return;
    grams = math.max(0, grams);
    if (_window.isNotEmpty) {
      final previous = _window.last;
      final gap = elapsedMs - previous.ms;
      if (gap <= 0) return;
      final change = grams - previous.grams;
      // Cup removal, tare and sudden load changes start a new segment, never
      // a spike. These generous limits are display heuristics, not shot limits.
      if (gap >= staleAfter.inMilliseconds ||
          change < -1 ||
          change > 1 + 20 * gap / 1000) {
        breakSegment();
      }
    }
    _window.add((ms: elapsedMs, grams: grams));
    while (_window.length > 2 && _window[1].ms <= elapsedMs - windowMs) {
      _window.removeAt(0);
    }
    final first = _window.first;
    final duration = elapsedMs - first.ms;
    if (duration < warmupMs) return;
    current = math.max(0, (grams - first.grams) * 1000 / duration);
    _points.add((
      elapsedMs: elapsedMs,
      value: current!,
      breakBefore: _breakNext,
    ));
    _snapshot = null;
    _breakNext = false;
  }
}

/// A reference derived from cup weight, retaining its original timer origin
/// and gaps. It neither extrapolates nor interpolates across missing readings.
class FlowGuide {
  FlowGuide._(this.points, this._times, this._weights);

  static FlowGuide? fromCurve(ShotCurve curve) {
    final times = curve.timesMs;
    if (times.length < 3 || curve.weight.length != times.length) return null;
    final trace = FlowTrace();
    for (var i = 0; i < times.length; i++) {
      if (times[i] < 0 || (i > 0 && times[i] <= times[i - 1])) return null;
      trace.add(times[i], curve.weight[i]);
    }
    final points = trace.points;
    if (points.length < 2 || !points.any((point) => point.value > 0)) {
      return null;
    }
    return FlowGuide._(points, List.of(times), List.of(curve.weight));
  }

  final List<GuidePoint> points;
  final List<int> _times;
  final List<double> _weights;
  int get endMs => points.last.elapsedMs;

  late final double finalWeightGrams = _weights
      .where((weight) => weight.isFinite && weight >= 0)
      .reduce(math.max);

  double? weightAt(int ms) {
    if (ms < _times.first || ms > _times.last) return null;
    var low = 0;
    var high = _times.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_times[middle] < ms) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final next = _weights[low];
    if (!next.isFinite || next < -0.3) return null;
    if (_times[low] == ms) return math.max(0, next);
    final previous = _weights[low - 1];
    final gap = _times[low] - _times[low - 1];
    final change = next - previous;
    if (!previous.isFinite ||
        previous < -0.3 ||
        gap >= FlowTrace.staleAfter.inMilliseconds ||
        change < -1 ||
        change > 1 + 20 * gap / 1000) {
      return null;
    }
    final fraction = (ms - _times[low - 1]) / gap;
    return math.max(0, previous + change * fraction);
  }

  double? targetAt(int ms) {
    if (ms < points.first.elapsedMs || ms > endMs) return null;
    var low = 0;
    var high = points.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (points[middle].elapsedMs < ms) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final next = points[low];
    if (next.elapsedMs == ms) return next.value;
    if (next.breakBefore) return null;
    final previous = points[low - 1];
    final fraction =
        (ms - previous.elapsedMs) / (next.elapsedMs - previous.elapsedMs);
    return previous.value + (next.value - previous.value) * fraction;
  }
}
