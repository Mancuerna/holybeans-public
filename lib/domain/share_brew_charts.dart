import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/shot_curve.dart';

class BrewShareChartData {
  const BrewShareChartData({
    required this.doseGrams,
    required this.beverageGrams,
    required this.tdsPercent,
    required this.methodName,
    this.category,
    this.recording,
  });

  final double? doseGrams;
  final double? beverageGrams;
  final double? tdsPercent;
  final String methodName;
  final String? category;
  final ({ShotCurve curve, String source})? recording;

  bool get espresso =>
      isEspressoMethod(category: category, methodName: methodName);
  double? get ey => extractionYieldPercent(
    doseGrams: doseGrams,
    beverageGrams: beverageGrams,
    tdsPercent: tdsPercent,
  );
  double? get ratio => switch ((beverageGrams, doseGrams)) {
    (final beverage?, final dose?) when dose > 0 => beverage / dose,
    _ => null,
  };
  bool get hasMap =>
      _positive(ey) && _positive(tdsPercent) && (!espresso || _positive(ratio));
  bool get hasCurve =>
      recording != null &&
      recording!.curve.timesMs.length >= 2 &&
      recording!.curve.durationMs > 0 &&
      recording!.curve.series.isNotEmpty;
  static bool _positive(double? value) =>
      value != null && value.isFinite && value > 0;
}
