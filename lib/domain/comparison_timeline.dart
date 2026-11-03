import 'dart:math' as math;

import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/shot_curve.dart';

typedef ComparisonPoint = ({int timeMs, double value});

enum ComparisonAlignment { start, firstDrip }

class ComparisonTimeline {
  ComparisonTimeline({
    required this.a,
    required this.b,
    this.firstDripA,
    this.firstDripB,
    ComparisonAlignment alignment = ComparisonAlignment.start,
  }) {
    this.alignment = alignment == ComparisonAlignment.firstDrip && canAlignDrip
        ? alignment
        : ComparisonAlignment.start;
  }

  final ComparisonCurve? a;
  final ComparisonCurve? b;
  final int? firstDripA;
  final int? firstDripB;
  late final ComparisonAlignment alignment;

  bool _validDrip(ComparisonCurve? curve, int? time) {
    if (curve == null || time == null || time < 0) return false;
    final points = CurveSeries.values.expand(curve.samples).toList();
    return points.isNotEmpty &&
        points.any((p) => p.timeMs <= time) &&
        points.any((p) => p.timeMs >= time);
  }

  late final bool canAlignDrip =
      _validDrip(a, firstDripA) && _validDrip(b, firstDripB);

  int offset(bool second) => alignment == ComparisonAlignment.firstDrip
      ? (second ? firstDripB! : firstDripA!)
      : 0;

  late final Map<bool, Map<CurveSeries, List<ComparisonPoint>>> _samples = {
    for (final second in [false, true])
      second: {
        for (final series in CurveSeries.values)
          series: _buildSamples(series, second: second),
      },
  };

  List<ComparisonPoint> samples(CurveSeries series, {required bool second}) =>
      _samples[second]![series]!;

  List<ComparisonPoint> _buildSamples(
    CurveSeries series, {
    required bool second,
  }) {
    final curve = second ? b : a;
    final points = curve?.samples(series) ?? <ComparisonPoint>[];
    // Keep duplicate timestamps (including brief pressure peaks) when drawing.
    // Sorting ties by their original position gives deterministic cursor values.
    final indexed = points.indexed.toList()
      ..sort((a, b) {
        final time = a.$2.timeMs.compareTo(b.$2.timeMs);
        return time != 0 ? time : a.$1.compareTo(b.$1);
      });
    final shift = offset(second);
    return [
      for (final (_, point) in indexed)
        (timeMs: point.timeMs - shift, value: point.value),
    ];
  }

  late final List<int> _times = [
    for (final second in [false, true])
      for (final series in CurveSeries.values)
        for (final point in samples(series, second: second)) point.timeMs,
  ];

  late final int minMs = _times.fold(0, math.min);
  late final int maxMs = math.max(minMs + 1000, _times.fold(0, math.max));

  double? at(CurveSeries series, double timeMs, {required bool second}) {
    if (!timeMs.isFinite) return null;
    final points = samples(series, second: second);
    if (points.isEmpty ||
        timeMs < points.first.timeMs ||
        timeMs > points.last.timeMs) {
      return null;
    }
    // Last sample at an identical timestamp wins; no division by zero.
    var low = 0;
    var high = points.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (points[mid].timeMs <= timeMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final before = points[low - 1];
    if (before.timeMs == timeMs || low == points.length) return before.value;
    final after = points[low];
    return before.value +
        (after.value - before.value) *
            (timeMs - before.timeMs) /
            (after.timeMs - before.timeMs);
  }

  double? difference(CurveSeries series, double timeMs) {
    if (a == null || b == null || !canOverlayCurves(a!, b!, series)) {
      return null;
    }
    final first = at(series, timeMs, second: false);
    final second = at(series, timeMs, second: true);
    return first == null || second == null ? null : second - first;
  }

  double? peak(CurveSeries series, {required bool second}) {
    final points = samples(series, second: second);
    return points.isEmpty ? null : points.map((p) => p.value).reduce(math.max);
  }
}
