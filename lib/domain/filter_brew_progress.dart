import 'dart:math' as math;

import 'package:holybeans/domain/shot_curve.dart';

/// Water recorded on the scale, kept when the dripper is lifted at the end.
double? recordedWaterGrams(ShotCurve? curve) {
  double? peak;
  for (final grams in curve?.weight ?? const <double>[]) {
    if (grams.isFinite && grams >= 0 && (peak == null || grams > peak)) {
      peak = grams;
    }
  }
  return peak;
}

/// Progress towards the water set before a filter brew starts.
class FilterBrewProgress {
  FilterBrewProgress({
    double? pouredGrams,
    double? doseGrams,
    double? targetWaterGrams,
  }) : pouredGrams = _nonnegative(pouredGrams),
       doseGrams = _positive(doseGrams),
       targetWaterGrams = _positive(targetWaterGrams);

  final double? pouredGrams;
  final double? doseGrams;
  final double? targetWaterGrams;

  double? get currentRatio => doseGrams == null || pouredGrams == null
      ? null
      : pouredGrams! / doseGrams!;

  double? get targetRatio => doseGrams == null || targetWaterGrams == null
      ? null
      : targetWaterGrams! / doseGrams!;

  double? get remainingGrams => targetWaterGrams == null
      ? null
      : math.max(0, targetWaterGrams! - (pouredGrams ?? 0));

  double? get excessGrams => targetWaterGrams == null || pouredGrams == null
      ? null
      : math.max(0, pouredGrams! - targetWaterGrams!);

  static double? _nonnegative(double? value) =>
      value != null && value.isFinite && value >= 0 ? value : null;

  static double? _positive(double? value) =>
      value != null && value.isFinite && value > 0 ? value : null;
}
