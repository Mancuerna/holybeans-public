import 'package:holybeans/domain/water_chemistry.dart';

enum WaterPreset {
  baristaHustle,
  hendon,
  raoPerger,
  holyWater,
  raoLotus,
  gwoNoSeaSalt,
  scaBh,
  melbourneBh,
  budapestBh,
  raoBh,
}

extension WaterPresetRecipe on WaterPreset {
  String get source => switch (this) {
    WaterPreset.raoPerger =>
      'https://coffeeadastra.com/2018/12/16/water-for-coffee-extraction/',
    WaterPreset.holyWater => 'https://espressoaf.com/guides/water.html',
    WaterPreset.raoLotus =>
      'https://lotuscoffeeproducts.com/pages/product-instructions',
    WaterPreset.gwoNoSeaSalt => 'https://gwo.coffee/pages/brewing',
    _ => 'https://www.baristahustle.com/diy-water-recipes-redux/',
  };

  Map<WaterSalt, double> gramsPerLitre(CalciumForm calcium) {
    if (this == WaterPreset.raoPerger) {
      // Gagné's 2018 recipe: each 200 g of solution provides 50 L.
      // Use the anhydrous reference and convert hydrates by moles.
      return {
        WaterSalt.epsom: 5 / 50,
        WaterSalt.magnesiumChloride: 2 / 50,
        WaterSalt.calciumChloride:
            (1.5 / 50) *
            saltMolarMass(WaterSalt.calciumChloride, calcium) /
            110.99,
        WaterSalt.sodiumBicarbonate: 1.7 / 50,
        WaterSalt.potassiumBicarbonate: 2 / 50,
      };
    }
    if (this == WaterPreset.holyWater) {
      // StriveForTone's published masses, divided from 10 L to 1 L.
      return {WaterSalt.epsom: .152, WaterSalt.potassiumBicarbonate: .046};
    }
    if (this == WaterPreset.gwoNoSeaSalt) {
      // GWO's 5 L recipe, explicitly omitting its 0.089 g of sea salt.
      return {WaterSalt.epsom: .332 / 5, WaterSalt.sodiumBicarbonate: .050 / 5};
    }
    if (this == WaterPreset.raoLotus) {
      // Lotus publishes each component in CaCO3 equivalents, not ion ppm.
      // Reproduce all four contributions with salts, including counterions.
      return {
        WaterSalt.magnesiumChloride:
            32.1 /
            saltContribution(WaterSalt.magnesiumChloride, calcium, 1).gh!,
        WaterSalt.calciumChloride:
            40.2 / saltContribution(WaterSalt.calciumChloride, calcium, 1).gh!,
        WaterSalt.sodiumBicarbonate:
            12.1 /
            saltContribution(WaterSalt.sodiumBicarbonate, calcium, 1).kh!,
        WaterSalt.potassiumBicarbonate:
            8 /
            saltContribution(WaterSalt.potassiumBicarbonate, calcium, 1).kh!,
      };
    }
    // Preserve the existing normalised targets; new BH adaptations use the
    // published GH/KH targets from the Redux concentrate recipes.
    final (gh, kh) = switch (this) {
      WaterPreset.baristaHustle => (80.0, 40.0),
      WaterPreset.hendon => (100.0, 31.0),
      WaterPreset.scaBh => (68.6, 40.1),
      WaterPreset.melbourneBh => (23.7, 11.5),
      WaterPreset.budapestBh => (51.2, 40.1),
      WaterPreset.raoBh => (75.7, 50.1),
      _ => throw StateError('Missing recipe for $name'),
    };
    return {
      WaterSalt.epsom: gh / saltContribution(WaterSalt.epsom, calcium, 1).gh!,
      WaterSalt.sodiumBicarbonate:
          kh / saltContribution(WaterSalt.sodiumBicarbonate, calcium, 1).kh!,
    };
  }

  WaterComposition get composition => waterFromSalts(
    gramsPerLitre(CalciumForm.anhydrous),
    1,
    CalciumForm.anhydrous,
  );
}

WaterComposition customWaterTarget(
  double gh,
  double kh,
  WaterSalt ghSource,
  WaterSalt khSource,
  CalciumForm calcium, {
  double? calciumGhFraction,
}) {
  if (calciumGhFraction != null &&
      (!calciumGhFraction.isFinite ||
          calciumGhFraction < 0 ||
          calciumGhFraction > 1 ||
          ghSource.group != WaterSaltGroup.magnesium)) {
    throw ArgumentError('Invalid hardness mixture');
  }
  if (!ghSource.contributesGh ||
      khSource.contributesGh ||
      !gh.isFinite ||
      !kh.isFinite ||
      gh < 0 ||
      kh < 0) {
    throw ArgumentError('Invalid water target');
  }
  return waterFromSalts(
    {
      ghSource:
          gh *
          (1 - (calciumGhFraction ?? 0)) /
          saltContribution(ghSource, calcium, 1).gh!,
      if (calciumGhFraction != null)
        WaterSalt.calciumChloride:
            gh *
            calciumGhFraction /
            saltContribution(WaterSalt.calciumChloride, calcium, 1).gh!,
      khSource: kh / saltContribution(khSource, calcium, 1).kh!,
    },
    1,
    calcium,
  );
}
