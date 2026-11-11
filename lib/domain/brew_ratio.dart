import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/domain/journal_codes.dart';

/// Extraction yield in percent: the share of the dose that ended up
/// dissolved in the cup. Null unless dose, beverage and TDS are positive.
double? extractionYieldPercent({
  double? doseGrams,
  double? beverageGrams,
  double? tdsPercent,
}) {
  if (doseGrams == null ||
      doseGrams <= 0 ||
      beverageGrams == null ||
      beverageGrams <= 0 ||
      tdsPercent == null ||
      tdsPercent <= 0) {
    return null;
  }
  return beverageGrams * tdsPercent / doseGrams;
}

/// Current recipe ratio, without rounding or changing manually entered water.
double? filterRecipeRatio(double? dose, double? water) =>
    dose != null &&
        dose.isFinite &&
        dose > 0 &&
        water != null &&
        water.isFinite &&
        water > 0
    ? water / dose
    : null;

bool isEspressoMethod({required String? category, required String methodName}) {
  final normalizedCategory = category?.trim().toLowerCase();
  return MethodCategory.fromCode(normalizedCategory) ==
          MethodCategory.espresso ||
      (normalizedCategory == null &&
          methodName.trim().toLowerCase() == 'espresso');
}

double? brewRatioTargetGrams({
  required double? doseGrams,
  required double ratio,
}) {
  if (doseGrams == null ||
      !doseGrams.isFinite ||
      doseGrams <= 0 ||
      !ratio.isFinite ||
      ratio <= 0) {
    return null;
  }
  final target = doseGrams * ratio;
  return target.isFinite ? target : null;
}

/// The espresso ratio a brew reached, in the target slider's 0.1 steps and
/// range (1:1 to 1:10), to aim the next shot at; null without dose and
/// beverage, or outside the supported slider range.
double? espressoTargetRatioOf({double? doseGrams, double? beverageGrams}) {
  final ratio = filterRecipeRatio(doseGrams, beverageGrams);
  if (ratio == null || ratio > 10) return null;
  return (ratio.clamp(1.0, 10.0) * 10).round() / 10;
}

String formatBrewRatioMultiplier(double ratio, String localeName) =>
    formatDecimal(ratio, pattern: '0.#', locale: localeName);

/// Returns a displayed 1:X brew ratio from the method's extraction measure.
/// Espresso uses beverage output; other methods use brew water.
String? formatBrewRatio({
  required String? methodCategory,
  required String methodName,
  required double? doseGrams,
  required double? waterGrams,
  required double? beverageGrams,
  required String localeName,
}) {
  if (doseGrams == null || !doseGrams.isFinite || doseGrams <= 0) return null;

  final measure =
      isEspressoMethod(category: methodCategory, methodName: methodName)
      ? beverageGrams
      : waterGrams;
  if (measure == null || !measure.isFinite || measure <= 0) return null;

  return '1:${formatBrewRatioMultiplier(measure / doseGrams, localeName)}';
}
