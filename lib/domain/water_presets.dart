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
  mitchOmni,
  alexLevitt,
  apaxKonflux,
  aviaryEspresso,
  aviaryFilter,
  bkgMoka,
  brewman,
  cafeByChris,
  hendonPotassium,
  coffeeRoastCo,
  danEils,
  glacial,
  fam29,
  fam69,
  melbourneAsami,
  nomad,
  norml,
  asamiDay1,
  asamiDay2,
  asamiDay3,
  asamiDay4,
  asamiDay5,
  asamiDay6,
  asamiDay7,
  asamiSoup,
  rpavlis,
  swQc,
  scenery,
  seyHouse,
  seyShop,
  stillCoffee,
  substance,
  subtext,
  terebat,
  chronicler,
  pickyChemist,
  twwEspresso,
  twwLight,
  wendelboeOslo,
  vibrant,
  wac2022,
  xliii,
}

// Published doses in grams per litre. CaCl₂ is normalized to anhydrous mass.
const _asamiRecipes = <WaterPreset, Map<WaterSalt, double>>{
  WaterPreset.mitchOmni: {
    WaterSalt.epsom: .108,
    WaterSalt.calciumChloride: .022,
    WaterSalt.sodiumBicarbonate: .054,
  },
  WaterPreset.alexLevitt: {
    WaterSalt.epsom: .049,
    WaterSalt.magnesiumChloride: .041,
    WaterSalt.calciumChloride: .022,
    WaterSalt.sodiumBicarbonate: .034,
  },
  WaterPreset.apaxKonflux: {
    WaterSalt.calciumChloride: 1.05 / 20 * 110.99 / 147.02,
    WaterSalt.sodiumBicarbonate: .507 / 20,
    WaterSalt.sodiumChloride: .353 / 20,
    WaterSalt.potassiumBicarbonate: .571 / 20,
    WaterSalt.potassiumChloride: .425 / 20,
  },
  WaterPreset.aviaryEspresso: {
    WaterSalt.epsom: .028,
    WaterSalt.calciumChloride: .010,
    WaterSalt.sodiumBicarbonate: .100,
  },
  WaterPreset.aviaryFilter: {
    WaterSalt.epsom: .095,
    WaterSalt.calciumChloride: .026,
    WaterSalt.sodiumBicarbonate: .044,
  },
  WaterPreset.bkgMoka: {
    WaterSalt.epsom: .133,
    WaterSalt.gypsum: .067,
    WaterSalt.sodiumBicarbonate: .013,
  },
  WaterPreset.brewman: {
    WaterSalt.epsom: .025,
    WaterSalt.calciumChloride: .044,
    WaterSalt.sodiumBicarbonate: .030,
  },
  WaterPreset.cafeByChris: {
    WaterSalt.epsom: .0368,
    WaterSalt.calciumChloride: .0166,
    WaterSalt.sodiumBicarbonate: .0168,
  },
  WaterPreset.hendonPotassium: {
    WaterSalt.epsom: .243,
    WaterSalt.potassiumBicarbonate: .062,
  },
  WaterPreset.coffeeRoastCo: {
    WaterSalt.epsom: .175,
    WaterSalt.calciumChloride: .050,
  },
  WaterPreset.danEils: {
    WaterSalt.magnesiumChloride: .100,
    WaterSalt.calciumChloride: .076,
    WaterSalt.potassiumBicarbonate: .100,
  },
  WaterPreset.glacial: {
    WaterSalt.magnesiumChloride: .0048,
    WaterSalt.epsom: .022,
    WaterSalt.calciumChloride: .0082,
    WaterSalt.calciumCarbonate: .016,
    WaterSalt.sodiumBicarbonate: .021,
    WaterSalt.potassiumBicarbonate: .0024,
  },
  WaterPreset.fam29: {WaterSalt.epsom: .049, WaterSalt.sodiumBicarbonate: .151},
  WaterPreset.fam69: {WaterSalt.epsom: .148, WaterSalt.sodiumBicarbonate: .151},
  WaterPreset.melbourneAsami: {
    WaterSalt.epsom: .122,
    WaterSalt.sodiumBicarbonate: .034,
  },
  WaterPreset.nomad: {
    WaterSalt.calciumChloride: .066,
    WaterSalt.magnesiumChloride: .040,
    WaterSalt.potassiumBicarbonate: .090,
    WaterSalt.sodiumBicarbonate: .008,
  },
  WaterPreset.norml: {
    WaterSalt.epsom: .0375,
    WaterSalt.gypsum: .050,
    WaterSalt.magnesiumChloride: .075,
    WaterSalt.sodiumChloride: .0175,
    WaterSalt.sodiumBicarbonate: .006,
  },
  WaterPreset.asamiDay1: {
    WaterSalt.epsom: .148,
    WaterSalt.sodiumBicarbonate: .025,
  },
  WaterPreset.asamiDay2: {
    WaterSalt.calciumChloride: .044,
    WaterSalt.sodiumBicarbonate: .025,
  },
  WaterPreset.asamiDay3: {
    WaterSalt.epsom: .100,
    WaterSalt.calciumChloride: .022,
    WaterSalt.sodiumBicarbonate: .025,
  },
  WaterPreset.asamiDay4: {
    WaterSalt.epsom: .050,
    WaterSalt.calciumChloride: .044,
    WaterSalt.sodiumBicarbonate: .025,
  },
  WaterPreset.asamiDay5: {
    WaterSalt.epsom: .074,
    WaterSalt.calciumChloride: .033,
    WaterSalt.potassiumBicarbonate: .030,
  },
  WaterPreset.asamiDay6: {
    WaterSalt.magnesiumChloride: .030,
    WaterSalt.epsom: .037,
    WaterSalt.calciumChloride: .017,
    WaterSalt.sodiumBicarbonate: .017,
    WaterSalt.potassiumBicarbonate: .010,
    WaterSalt.sodiumChloride: .015,
  },
  WaterPreset.asamiDay7: {
    WaterSalt.epsom: .037,
    WaterSalt.calciumChloride: .017,
    WaterSalt.sodiumBicarbonate: .008,
    WaterSalt.potassiumBicarbonate: .010,
    WaterSalt.sodiumChloride: .020,
  },
  WaterPreset.asamiSoup: {
    WaterSalt.epsom: .037,
    WaterSalt.magnesiumChloride: .010,
    WaterSalt.calciumChloride: .0055,
    WaterSalt.sodiumBicarbonate: .100,
    WaterSalt.potassiumBicarbonate: .020,
    WaterSalt.sodiumChloride: .010,
  },
  WaterPreset.rpavlis: {WaterSalt.potassiumBicarbonate: .100},
  WaterPreset.swQc: {WaterSalt.epsom: .172, WaterSalt.sodiumBicarbonate: .076},
  WaterPreset.scenery: {
    WaterSalt.calciumChloride: .040,
    WaterSalt.sodiumBicarbonate: .030,
  },
  WaterPreset.seyHouse: {
    WaterSalt.magnesiumChloride: .030,
    WaterSalt.calciumChloride: .022,
    WaterSalt.potassiumBicarbonate: .020,
  },
  WaterPreset.seyShop: {
    WaterSalt.calciumChloride: .024 * 110.99 / 147.02,
    WaterSalt.epsom: .014,
    WaterSalt.sodiumBicarbonate: .018,
    WaterSalt.potassiumBicarbonate: .0017,
  },
  WaterPreset.stillCoffee: {
    WaterSalt.magnesiumChloride: 11 * 203.30 / (1000 * calciumCarbonateMass),
    WaterSalt.calciumChloride: 27 * 110.99 / (1000 * calciumCarbonateMass),
    WaterSalt.potassiumBicarbonate:
        20 * 2 * 100.115 / (1000 * calciumCarbonateMass),
  },
  WaterPreset.substance: {
    WaterSalt.gypsum: .108,
    WaterSalt.epsom: .066,
    WaterSalt.sodiumBicarbonate: .066,
  },
  WaterPreset.subtext: {
    WaterSalt.calciumChloride: .042,
    WaterSalt.epsom: .092,
    WaterSalt.sodiumBicarbonate: .042,
  },
  WaterPreset.terebat: {
    WaterSalt.magnesiumChloride: .04,
    WaterSalt.sodiumBicarbonate: .01,
    WaterSalt.sodiumChloride: .02,
  },
  WaterPreset.chronicler: {
    WaterSalt.calciumChloride: .037 * 110.99 / 147.02,
    WaterSalt.gypsum: .026,
    WaterSalt.sodiumBicarbonate: .017,
    WaterSalt.sodiumChloride: .014,
  },
  WaterPreset.pickyChemist: {
    WaterSalt.epsom: .155,
    WaterSalt.sodiumBicarbonate: .040,
  },
  WaterPreset.twwEspresso: {
    WaterSalt.epsom: .394,
    WaterSalt.sodiumBicarbonate: .113,
  },
  WaterPreset.twwLight: {
    WaterSalt.epsom: .408,
    WaterSalt.sodiumBicarbonate: .080,
  },
  WaterPreset.wendelboeOslo: {
    WaterSalt.calciumChloride: .041,
    WaterSalt.sodiumBicarbonate: .047,
  },
  WaterPreset.vibrant: {
    WaterSalt.calciumChloride: .053,
    WaterSalt.magnesiumChloride: .098,
    WaterSalt.sodiumBicarbonate: .040,
    WaterSalt.potassiumBicarbonate: .048,
  },
  WaterPreset.wac2022: {
    WaterSalt.magnesiumChloride: .102,
    WaterSalt.calciumChloride: .055,
    WaterSalt.sodiumBicarbonate: .084,
  },
  WaterPreset.xliii: {WaterSalt.epsom: .8 / 5},
};

extension WaterPresetRecipe on WaterPreset {
  String get source => switch (this) {
    WaterPreset.raoPerger =>
      'https://coffeeadastra.com/2018/12/16/water-for-coffee-extraction/',
    WaterPreset.holyWater => 'https://espressoaf.com/guides/water.html',
    WaterPreset.raoLotus =>
      'https://lotuscoffeeproducts.com/pages/product-instructions',
    WaterPreset.gwoNoSeaSalt => 'https://gwo.coffee/pages/brewing',
    _ when _asamiRecipes.containsKey(this) =>
      'https://www.robertasami.com/water',
    _ => 'https://www.baristahustle.com/diy-water-recipes-redux/',
  };

  Map<WaterSalt, double> gramsPerLitre(CalciumForm calcium) {
    final published = _asamiRecipes[this];
    if (published != null) {
      return {
        ...published,
        if (published[WaterSalt.calciumChloride] case final mass?)
          WaterSalt.calciumChloride:
              mass * saltMolarMass(WaterSalt.calciumChloride, calcium) / 110.99,
      };
    }
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
  if (!ghSource.isHardnessSource ||
      khSource.group != WaterSaltGroup.alkalinity ||
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
