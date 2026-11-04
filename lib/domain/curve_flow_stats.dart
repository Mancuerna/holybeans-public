import 'dart:math' as math;

import 'package:holybeans/domain/curve_sampling.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Statistics of recorded flow, weighted by elapsed time rather than sample
/// count. Linear segments keep the results invariant when pressure timestamps
/// are inserted. Zero flow during pauses is included, as are signed readings.
class CurveFlowStats {
  const CurveFlowStats({
    required this.startMs,
    required this.endMs,
    required this.mean,
    required this.median,
    this.max,
  });

  /// Explicit first drip when valid, otherwise the interpolated crossing of
  /// 0.1 g in the cup. The fallback is an estimate from the curve, not a new
  /// first-drip measurement written to the diary.
  static CurveFlowStats? fromCurve(ShotCurve curve, {int? firstDripMs}) {
    if (curve.flow.isEmpty || curve.timesMs.length < 2) return null;
    if (curve.timesMs.any((t) => t < 0) ||
        curve.flow.any((f) => !f.isFinite) ||
        curve.weight.any((w) => !w.isFinite)) {
      return null;
    }
    for (var i = 1; i < curve.timesMs.length; i++) {
      if (curve.timesMs[i] <= curve.timesMs[i - 1]) return null;
    }
    final start = firstDripMs != null && firstDripMs >= 0
        ? firstDripMs.clamp(curve.timesMs.first, curve.durationMs).toDouble()
        : _firstDrip(curve);
    if (start == null || start >= curve.durationMs) return null;
    final times = <int>{
      start.ceil(),
      for (final time in curve.timesMs)
        if (time > start) time,
    }.toList()..sort();
    if (times.length < 2) return null;
    final values = resampleCurveSeries(curve.timesMs, curve.flow, times);
    final segments = <({double a, double b, int ms})>[];
    var integral = 0.0;
    for (var i = 1; i < times.length; i++) {
      final ms = times[i] - times[i - 1];
      final a = values[i - 1];
      final b = values[i];
      integral += (a + b) / 2 * ms;
      segments.add((a: math.min(a, b), b: math.max(a, b), ms: ms));
    }
    final duration = times.last - times.first;
    final lowest = values.reduce(math.min);
    final highest = values.reduce(math.max);
    // The lower and upper searches normally visit identical candidates.
    // Evaluate the time distribution once per candidate, with segment bounds
    // already ordered. Keep the original arithmetic and plateau convention.
    final distribution = <double, double>{};
    double below(double value) => distribution.putIfAbsent(value, () {
      var durationBelow = 0.0;
      for (final segment in segments) {
        if (value >= segment.b) {
          durationBelow += segment.ms;
        } else if (value > segment.a) {
          durationBelow +=
              (value - segment.a) / (segment.b - segment.a) * segment.ms;
        }
      }
      return durationBelow;
    });
    double quantile({required bool upper}) {
      var low = lowest;
      var high = highest;
      for (var n = 0; n < 48; n++) {
        final value = (low + high) / 2;
        final elapsed = below(value);
        if (upper ? elapsed <= duration / 2 : elapsed < duration / 2) {
          low = value;
        } else {
          high = value;
        }
      }
      return (low + high) / 2;
    }

    return CurveFlowStats(
      startMs: times.first,
      endMs: times.last,
      mean: integral / duration,
      median: (quantile(upper: false) + quantile(upper: true)) / 2,
      max: highest,
    );
  }

  static double? _firstDrip(ShotCurve curve) {
    if (curve.weight.isEmpty) return null;
    for (var i = 0; i < curve.weight.length; i++) {
      if (curve.weight[i] < 0.1) continue;
      if (i == 0) return curve.timesMs.first.toDouble();
      final before = curve.weight[i - 1];
      final fraction = (0.1 - before) / (curve.weight[i] - before);
      return curve.timesMs[i - 1] +
          fraction * (curve.timesMs[i] - curve.timesMs[i - 1]);
    }
    return null;
  }

  final int startMs;
  final int endMs;
  final double mean;
  final double median;

  /// Highest flow in the same window: from the first drip on, so filling
  /// the basket or the bed does not pass for the peak in the cup.
  final double? max;
}
