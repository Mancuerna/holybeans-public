/// A division in milligrams, matching inventory's three decimal places.
class FreezePlan {
  FreezePlan({required double totalGrams, required double portionGrams}) {
    if (!totalGrams.isFinite ||
        !portionGrams.isFinite ||
        totalGrams <= 0 ||
        portionGrams <= 0) {
      throw ArgumentError('Weights must be positive and finite');
    }
    final total = (totalGrams * 1000).round();
    final portion = (portionGrams * 1000).round();
    if (portion <= 0 || total < portion) {
      throw ArgumentError('Portion must fit in total');
    }
    count = total ~/ portion;
    if (count > 500) throw ArgumentError('Too many portions');
    grams = portion / 1000;
    remainder = (total % portion) / 1000;
  }

  late final int count;
  late final double grams;
  late final double remainder;

  List<double> amounts({required bool includeRemainder}) => [
    for (var i = 0; i < count; i++) grams,
    if (includeRemainder && remainder > 0) remainder,
  ];
}

/// Frozen coffee needed for a dose after using the available fresh coffee.
double frozenGramsNeeded(double? dose, double? available) {
  if (dose == null || available == null || !dose.isFinite || dose <= 0) {
    return 0;
  }
  return (dose - available.clamp(0, double.infinity)).clamp(0, dose);
}
