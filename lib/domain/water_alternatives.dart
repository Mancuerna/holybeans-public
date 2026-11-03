import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_chemistry.dart';

List<WaterRecipe> waterAlternatives(WaterRecipe automatic) {
  final target = automatic.target;
  final options = [automatic];
  if (target == null ||
      (automatic.mode == WaterCalculationMode.custom &&
          !automatic.ionTargets)) {
    return options;
  }
  final available = automatic.availableSalts ?? WaterSalt.values.toSet();
  final magnesium = [
    for (final salt in [WaterSalt.epsom, WaterSalt.magnesiumChloride])
      if (available.contains(salt)) salt,
  ];
  final alkalinity = [
    for (final salt in [
      WaterSalt.sodiumBicarbonate,
      WaterSalt.potassiumBicarbonate,
    ])
      if (available.contains(salt)) salt,
  ];
  for (final mg in magnesium.isEmpty ? <WaterSalt?>[null] : magnesium) {
    for (final kh in alkalinity.isEmpty ? <WaterSalt?>[null] : alkalinity) {
      final allowed = {
        ?mg,
        ?kh,
        if (available.contains(WaterSalt.calciumChloride))
          WaterSalt.calciumChloride,
      };
      try {
        final grams = adjustWaterToIons(
          base: automatic.base,
          target: target,
          litres: automatic.litres,
          calcium: automatic.calcium,
          allowed: allowed,
        );
        final candidate = WaterRecipe(
          litres: automatic.litres,
          calcium: automatic.calcium,
          mode: automatic.mode,
          base: automatic.base,
          grams: grams,
          target: target,
          presetId: automatic.presetId,
          ghSource: automatic.ghSource,
          khSource: automatic.khSource,
          calciumGhFraction: automatic.calciumGhFraction,
          ionTargets: automatic.ionTargets,
          availableSalts: available,
        );
        final result = candidate.result;
        bool matches(double? actual, double? goal) =>
            actual != null && goal != null && (actual - goal).abs() < .01;
        if (!matches(result[WaterIon.calcium], target[WaterIon.calcium]) ||
            !matches(result[WaterIon.magnesium], target[WaterIon.magnesium]) ||
            !matches(result.kh, target.kh)) {
          continue;
        }
        if (options.any((other) => sameWaterDoses(other, candidate))) continue;
        options.add(candidate);
      } on ArgumentError {
        // An incomplete base or unavailable source cannot offer this alternative.
      }
    }
  }
  return List.unmodifiable(options);
}

bool sameWaterDoses(WaterRecipe a, WaterRecipe b) => WaterSalt.values.every(
  (salt) =>
      (a.grams[salt]! / a.litres - b.grams[salt]! / b.litres).abs() < 1e-7,
);
