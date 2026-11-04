import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/shot_curve.dart';

typedef CurveRequest = ({ShotCurve curve, int? firstDripMs});

/// One coherent rendering snapshot. Cursor values and statistics use all
/// samples; only the polyline is reduced for display.
class PreparedCurve {
  PreparedCurve({
    required this.recorded,
    required this.shown,
    required this.display,
    required this.peaks,
    required this.flowStats,
  });

  final ShotCurve recorded;
  final ShotCurve shown;
  final ShotCurve display;
  final Map<CurveSeries, double> peaks;
  final CurveFlowStats? flowStats;
}

PreparedCurve prepareCurve(CurveRequest request) {
  final curve = request.curve;
  final shown = curve.smoothed();
  return PreparedCurve(
    recorded: curve,
    shown: shown,
    display: displayCurve(shown),
    peaks: {
      for (final series in curve.series)
        series: series == CurveSeries.pressure
            ? curve.maxOf(series)
            : curve.peakOf(series),
    },
    flowStats: CurveFlowStats.fromCurve(
      curve,
      firstDripMs: request.firstDripMs,
    ),
  );
}

/// Keeps both endpoints and the minimum/maximum of every series in each
/// bucket, bounding drawing work while retaining each bucket's extrema.
/// Original timestamps are retained, including irregular sampling.
ShotCurve displayCurve(ShotCurve curve, {int maxPoints = 1024}) {
  final allSeries = curve.series;
  final count = curve.timesMs.length;
  if (count <= maxPoints || allSeries.isEmpty) return curve;
  if (maxPoints < 2 + allSeries.length * 2) {
    throw ArgumentError.value(
      maxPoints,
      'maxPoints',
      'Too small to retain extrema',
    );
  }
  final buckets = (maxPoints - 2) ~/ (allSeries.length * 2);
  final kept = <int>{0, count - 1};
  for (var bucket = 0; bucket < buckets; bucket++) {
    final start = bucket * count ~/ buckets;
    final end = (bucket + 1) * count ~/ buckets;
    for (final series in allSeries) {
      final values = curve.values(series);
      var low = start;
      var high = start;
      for (var i = start + 1; i < end; i++) {
        if (values[i] < values[low]) low = i;
        if (values[i] > values[high]) high = i;
      }
      kept
        ..add(low)
        ..add(high);
    }
  }
  final indices = kept.toList()..sort();
  List<double> take(List<double> values) =>
      values.isEmpty ? const [] : [for (final i in indices) values[i]];
  return ShotCurve(
    timesMs: [for (final i in indices) curve.timesMs[i]],
    pressure: take(curve.pressure),
    flow: take(curve.flow),
    weight: take(curve.weight),
  );
}
