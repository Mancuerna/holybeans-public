import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

String formatDoseGrams(double grams) => NumberFormat(
  grams < .1 ? '0.000####' : '0.000',
  regionalLocale.toString(),
).format(grams);

WaterComposition compositionOf(WaterProfile profile) => WaterComposition(
  measuredGh: profile.ghPpmAsCaCO3,
  measuredKh: profile.khPpmAsCaCO3,
  ions: {
    WaterIon.calcium: profile.calciumPpm,
    WaterIon.magnesium: profile.magnesiumPpm,
    WaterIon.sodium: profile.sodiumPpm,
    WaterIon.potassium: profile.potassiumPpm,
    WaterIon.chloride: profile.chloridePpm,
    WaterIon.sulfate: profile.sulfatePpm,
    WaterIon.bicarbonate: profile.bicarbonatePpm,
  },
);

double? addedPotassiumOf(WaterProfile profile) {
  if (profile.potassiumPpm != null || profile.recipeJson == null) return null;
  try {
    final recipe = WaterRecipe.fromJson(profile.recipeJson!);
    if (recipe.base[WaterIon.potassium] != null) return null;
    final added = recipe.added[WaterIon.potassium]!;
    return added > 0 ? added : null;
  } on FormatException {
    return null;
  }
}

String ionLabel(AppLocalizations s, WaterIon ion) => switch (ion) {
  WaterIon.calcium => s.calcium,
  WaterIon.magnesium => s.magnesium,
  WaterIon.sodium => s.sodium,
  WaterIon.potassium => s.potassium,
  WaterIon.chloride => s.chloride,
  WaterIon.sulfate => s.sulfate,
  WaterIon.bicarbonate => s.waterBicarbonate,
};

String saltLabel(AppLocalizations s, WaterSalt salt) => switch (salt) {
  WaterSalt.calciumCarbonate => s.waterCarbonateCO2,
  WaterSalt.gypsum => s.waterSaltGypsum,
  WaterSalt.sodiumChloride => s.waterSaltSodiumChloride,
  WaterSalt.potassiumChloride => s.waterSaltPotassiumChloride,
  WaterSalt.epsom => s.waterSaltEpsom,
  WaterSalt.magnesiumChloride => s.waterSaltMagnesiumChloride,
  WaterSalt.calciumChloride => s.waterSaltCalciumChloride,
  WaterSalt.sodiumBicarbonate => s.waterSaltSodiumBicarbonate,
  WaterSalt.potassiumBicarbonate => s.waterSaltPotassiumBicarbonate,
};

String presetLabel(AppLocalizations s, WaterPreset preset) => switch (preset) {
  WaterPreset.mitchOmni => s.waterPresetMitchOmni,
  WaterPreset.alexLevitt => s.waterPresetAlexLevitt,
  WaterPreset.apaxKonflux => s.waterPresetApaxKonflux,
  WaterPreset.aviaryEspresso => s.waterPresetAviaryEspresso,
  WaterPreset.aviaryFilter => s.waterPresetAviaryFilter,
  WaterPreset.bkgMoka => s.waterPresetBkgMoka,
  WaterPreset.brewman => s.waterPresetBrewman,
  WaterPreset.cafeByChris => s.waterPresetCafeByChris,
  WaterPreset.hendonPotassium => s.waterPresetHendonPotassium,
  WaterPreset.coffeeRoastCo => s.waterPresetCoffeeRoastCo,
  WaterPreset.danEils => s.waterPresetDanEils,
  WaterPreset.glacial => s.waterPresetGlacial,
  WaterPreset.fam29 => s.waterPresetFam29,
  WaterPreset.fam69 => s.waterPresetFam69,
  WaterPreset.melbourneAsami => s.waterPresetMelbourneAsami,
  WaterPreset.nomad => s.waterPresetNomad,
  WaterPreset.norml => s.waterPresetNorml,
  WaterPreset.asamiDay1 => s.waterPresetAsamiDay1,
  WaterPreset.asamiDay2 => s.waterPresetAsamiDay2,
  WaterPreset.asamiDay3 => s.waterPresetAsamiDay3,
  WaterPreset.asamiDay4 => s.waterPresetAsamiDay4,
  WaterPreset.asamiDay5 => s.waterPresetAsamiDay5,
  WaterPreset.asamiDay6 => s.waterPresetAsamiDay6,
  WaterPreset.asamiDay7 => s.waterPresetAsamiDay7,
  WaterPreset.asamiSoup => s.waterPresetAsamiSoup,
  WaterPreset.rpavlis => s.waterPresetRpavlis,
  WaterPreset.swQc => s.waterPresetSwQc,
  WaterPreset.scenery => s.waterPresetScenery,
  WaterPreset.seyHouse => s.waterPresetSeyHouse,
  WaterPreset.seyShop => s.waterPresetSeyShop,
  WaterPreset.stillCoffee => s.waterPresetStillCoffee,
  WaterPreset.substance => s.waterPresetSubstance,
  WaterPreset.subtext => s.waterPresetSubtext,
  WaterPreset.terebat => s.waterPresetTerebat,
  WaterPreset.chronicler => s.waterPresetChronicler,
  WaterPreset.pickyChemist => s.waterPresetPickyChemist,
  WaterPreset.twwEspresso => s.waterPresetTwwEspresso,
  WaterPreset.twwLight => s.waterPresetTwwLight,
  WaterPreset.wendelboeOslo => s.waterPresetWendelboeOslo,
  WaterPreset.vibrant => s.waterPresetVibrant,
  WaterPreset.wac2022 => s.waterPresetWac2022,
  WaterPreset.xliii => s.waterPresetXliii,
  WaterPreset.baristaHustle => s.waterPresetBh,
  WaterPreset.hendon => s.waterPresetHendon,
  WaterPreset.raoPerger => s.waterPresetRaoPerger,
  WaterPreset.holyWater => s.waterPresetHoly,
  WaterPreset.raoLotus => s.waterPresetRaoLotus,
  WaterPreset.gwoNoSeaSalt => s.waterPresetGwo,
  WaterPreset.scaBh => s.waterPresetScaBh,
  WaterPreset.melbourneBh => s.waterPresetMelbourneBh,
  WaterPreset.budapestBh => s.waterPresetBudapestBh,
  WaterPreset.raoBh => s.waterPresetRaoBh,
};

String ionSymbol(WaterIon ion) => switch (ion) {
  WaterIon.calcium => 'Ca',
  WaterIon.magnesium => 'Mg',
  WaterIon.sodium => 'Na',
  WaterIon.potassium => 'K',
  WaterIon.chloride => 'Cl',
  WaterIon.sulfate => 'SO₄',
  WaterIon.bicarbonate => 'HCO₃',
};

String? presetHint(AppLocalizations s, WaterPreset preset) => switch (preset) {
  WaterPreset.stillCoffee => s.waterHintStillCoffee,
  WaterPreset.aviaryFilter => s.waterHintAviaryFilter,
  WaterPreset.terebat => s.waterHintTerebat,
  WaterPreset.chronicler => s.waterHintChronicler,
  WaterPreset.pickyChemist => s.waterHintPickyChemist,
  WaterPreset.gwoNoSeaSalt => s.waterPresetGwoHint,
  WaterPreset.raoLotus => s.waterPresetRaoLotusHint,
  WaterPreset.scaBh ||
  WaterPreset.melbourneBh ||
  WaterPreset.budapestBh ||
  WaterPreset.raoBh => s.waterPresetBhAdaptationHint,
  _ => null,
};
