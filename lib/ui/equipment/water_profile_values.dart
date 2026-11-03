import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';

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
  WaterSalt.epsom => s.waterSaltEpsom,
  WaterSalt.magnesiumChloride => s.waterSaltMagnesiumChloride,
  WaterSalt.calciumChloride => s.waterSaltCalciumChloride,
  WaterSalt.sodiumBicarbonate => s.waterSaltSodiumBicarbonate,
  WaterSalt.potassiumBicarbonate => s.waterSaltPotassiumBicarbonate,
};

String presetLabel(AppLocalizations s, WaterPreset preset) => switch (preset) {
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
  WaterPreset.gwoNoSeaSalt => s.waterPresetGwoHint,
  WaterPreset.raoLotus => s.waterPresetRaoLotusHint,
  WaterPreset.scaBh ||
  WaterPreset.melbourneBh ||
  WaterPreset.budapestBh ||
  WaterPreset.raoBh => s.waterPresetBhAdaptationHint,
  _ => null,
};
