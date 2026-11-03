/// Water added for one bloom divided by the coffee dose, never cumulative water.
double? bloomWaterRatio(double? waterGrams, double? doseGrams) {
  if (waterGrams == null ||
      doseGrams == null ||
      !waterGrams.isFinite ||
      !doseGrams.isFinite ||
      waterGrams <= 0 ||
      doseGrams <= 0) {
    return null;
  }
  final ratio = waterGrams / doseGrams;
  return ratio.isFinite ? ratio : null;
}
