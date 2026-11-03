import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_alternatives.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';

class WaterCalculatorModel extends ChangeNotifier {
  WaterCalculatorModel({WaterRecipe? seed, WaterProfile? initialWater}) {
    if (seed != null) {
      _loadRecipe(seed);
    } else if (initialWater != null) {
      mineralWater = true;
      _setBase(compositionOf(initialWater));
    }
    for (final field in fields) {
      field.addListener(recalculate);
    }
    _manualVolume = seed?.litres ?? 1;
    recalculate();
    if (seed != null) {
      final index = alternatives.indexWhere((r) => sameWaterDoses(r, seed));
      if (index >= 0) selectAlternative(index);
    }
  }

  final litres = TextEditingController(text: '1');
  final calciumPercent = TextEditingController(text: '50');
  final targetGh = TextEditingController(text: '80');
  final targetKh = TextEditingController(text: '40');
  final baseGh = TextEditingController();
  final baseKh = TextEditingController();
  final ions = {
    for (final ion in WaterIon.values) ion: TextEditingController(),
  };
  final targetIons = {
    for (final ion in WaterIon.values)
      ion: TextEditingController(
        text: switch (ion) {
          WaterIon.calcium => '16',
          WaterIon.magnesium => '10',
          _ => '',
        },
      ),
  };
  final amounts = {
    for (final salt in WaterSalt.values) salt: TextEditingController(text: '0'),
  };
  Iterable<TextEditingController> get fields => [
    litres,
    targetGh,
    calciumPercent,
    targetKh,
    baseGh,
    baseKh,
    ...ions.values,
    ...targetIons.values,
    ...amounts.values,
  ];
  bool mineralWater = false;
  bool useSavedWater = false;
  String? savedBaseId;
  bool mixHardness = false;
  bool ionTargets = true;
  bool missingMixtureBase = false;
  bool missingBase = false;
  bool missingTarget = false;
  bool isSavedTarget = false;
  String? savedTargetId;
  String? savedTargetName;

  String get targetSelection => isSavedTarget
      ? savedTargetId == null
            ? 'saved-target'
            : 'water:$savedTargetId'
      : 'preset:${preset.name}';

  bool get _savedIonTarget =>
      isSavedTarget &&
      _savedTarget?[WaterIon.calcium] != null &&
      _savedTarget?[WaterIon.magnesium] != null;

  WaterCalculationMode mode = WaterCalculationMode.preset;
  WaterPreset preset = WaterPreset.baristaHustle;
  CalciumForm calcium = CalciumForm.dihydrate;
  WaterSalt ghSource = WaterSalt.epsom;
  WaterSalt khSource = WaterSalt.sodiumBicarbonate;
  final Set<WaterSalt> availableSalts = {
    WaterSalt.epsom,
    WaterSalt.calciumChloride,
    WaterSalt.sodiumBicarbonate,
  };
  WaterRecipe? recipe;
  List<WaterRecipe> alternatives = [];
  int selectedAlternative = 0;

  void selectAlternative(int index) {
    recipe = alternatives[index];
    selectedAlternative = index;
    notifyListeners();
  }

  WaterComposition? initialComposition;
  WaterComposition? _savedTarget;
  bool _settingFields = false;
  double _manualVolume = 1;

  void _loadRecipe(WaterRecipe seed) {
    litres.text = fieldExact(seed.litres);
    calcium = seed.calcium;
    mode = seed.mode;
    preset =
        WaterPreset.values.where((p) => p.name == seed.presetId).firstOrNull ??
        WaterPreset.baristaHustle;
    ghSource = seed.ghSource;
    khSource = seed.khSource;
    mixHardness = seed.calciumGhFraction != null;
    ionTargets = seed.ionTargets;
    availableSalts
      ..clear()
      ..addAll(seed.availableSalts ?? WaterSalt.values);
    calciumPercent.text = fieldExact((seed.calciumGhFraction ?? .5) * 100);
    targetGh.text = fieldExact(seed.target?.gh ?? 80);
    targetKh.text = fieldExact(seed.target?.kh ?? 40);
    for (final salt in WaterSalt.values) {
      amounts[salt]!.text = fieldExact(seed.grams[salt]);
    }
    if (seed.ionTargets) {
      for (final ion in WaterIon.values) {
        targetIons[ion]!.text = fieldExact(seed.target?[ion]);
      }
    }
    _setBase(seed.base);
    mineralWater =
        seed.base.ions.values.any((v) => v == null || v != 0) ||
        seed.base.gh != 0 ||
        seed.base.kh != 0;
    _savedTarget = seed.target;
    isSavedTarget =
        seed.mode == WaterCalculationMode.preset && seed.presetId == null;
  }

  double? _read(TextEditingController field) {
    final text = field.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = parseNumber(text);
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('Invalid number');
    }
    return value;
  }

  void _setBase(WaterComposition water) {
    for (final ion in WaterIon.values) {
      ions[ion]!.text = fieldExact(water[ion]);
    }
    baseGh.text = fieldExact(water.measuredGh);
    baseKh.text = fieldExact(water.kh);
  }

  void useWater(WaterProfile profile) {
    _settingFields = true;
    mineralWater = true;
    useSavedWater = true;
    savedBaseId = profile.id;
    _setBase(compositionOf(profile));
    _settingFields = false;
    recalculate();
  }

  void useTarget(WaterProfile profile) {
    mode = WaterCalculationMode.preset;
    isSavedTarget = true;
    savedTargetId = profile.id;
    savedTargetName = profile.name;
    _savedTarget = compositionOf(profile);
    recalculate();
  }

  void setSalt(WaterSalt salt, bool selected) {
    _settingFields = true;
    if (selected) {
      availableSalts.add(salt);
    } else {
      availableSalts.remove(salt);
      amounts[salt]!.text = '0';
    }
    _settingFields = false;
    recalculate();
  }

  Set<WaterSalt> get missingPresetSalts => isSavedTarget
      ? {}
      : preset
            .gramsPerLitre(calcium)
            .entries
            .where((e) => e.value > 0 && !availableSalts.contains(e.key))
            .map((e) => e.key)
            .toSet();

  void usePresetSalts() {
    availableSalts.addAll(missingPresetSalts);
    recalculate();
  }

  void choosePreset(WaterPreset value) {
    preset = value;
    isSavedTarget = false;
    savedTargetId = null;
    savedTargetName = null;
    _savedTarget = null;
    recalculate();
  }

  void chooseMode(WaterCalculationMode value) {
    if (value == WaterCalculationMode.quantities && recipe != null) {
      _settingFields = true;
      for (final salt in WaterSalt.values) {
        amounts[salt]!.text = fieldExact(recipe!.grams[salt]);
      }
      _manualVolume = recipe!.litres;
      _settingFields = false;
    }
    mode = value;
    isSavedTarget = false;
    savedTargetId = null;
    savedTargetName = null;
    _savedTarget = null;
    recalculate();
  }

  Map<WaterSalt, double> _manualGrams(double volume) {
    final values = {
      for (final salt in availableSalts) salt: _read(amounts[salt]!) ?? 0,
    };
    if (volume != _manualVolume) {
      _settingFields = true;
      for (final salt in availableSalts) {
        values[salt] = values[salt]! * volume / _manualVolume;
        amounts[salt]!.text = fieldExact(values[salt]);
      }
      _manualVolume = volume;
      _settingFields = false;
    }
    return values;
  }

  WaterComposition _target(double? fraction) {
    if (mode == WaterCalculationMode.preset) {
      return _savedTarget ?? preset.composition;
    }
    if (!ionTargets) {
      return customWaterTarget(
        _read(targetGh) ?? (throw const FormatException('Missing GH')),
        _read(targetKh) ?? (throw const FormatException('Missing KH')),
        ghSource,
        khSource,
        calcium,
        calciumGhFraction: fraction,
      );
    }
    final target = WaterComposition(
      ions: {for (final ion in WaterIon.values) ion: _read(targetIons[ion]!)},
      measuredKh: _read(targetKh),
    );
    if (target.gh == null || target.kh == null) {
      throw const FormatException('Missing primary targets');
    }
    return target;
  }

  Map<WaterSalt, double> _adjust(
    WaterComposition base,
    WaterComposition target,
    double volume,
    double? fraction,
  ) {
    if (mode == WaterCalculationMode.preset &&
        !mineralWater &&
        _savedTarget == null &&
        missingPresetSalts.isEmpty) {
      return preset
          .gramsPerLitre(calcium)
          .map((s, g) => MapEntry(s, g * volume));
    }
    if ((mode == WaterCalculationMode.custom && ionTargets) ||
        _savedIonTarget) {
      return adjustWaterToIons(
        base: base,
        target: target,
        litres: volume,
        calcium: calcium,
        allowed: availableSalts,
      );
    }
    if (fraction != null) {
      return adjustWaterMixture(
        base: base,
        target: target,
        litres: volume,
        calcium: calcium,
        magnesiumSource: ghSource,
        khSource: khSource,
        allowed: availableSalts,
      );
    }
    return adjustWater(
      base: base,
      target: target,
      litres: volume,
      calcium: calcium,
      allowed: mode == WaterCalculationMode.custom
          ? {ghSource, khSource}.intersection(availableSalts)
          : availableSalts,
      allowPartial: true,
    );
  }

  void recalculate() {
    if (_settingFields) return;
    final previous = recipe;
    recipe = null;
    alternatives = [];
    selectedAlternative = 0;
    initialComposition = null;
    missingBase = false;
    missingTarget = false;
    missingMixtureBase = false;
    try {
      final volume = _read(litres);
      if (volume == null || volume <= 0 || volume > 10000) {
        throw const FormatException('Invalid volume');
      }
      final base = mineralWater
          ? WaterComposition(
              ions: {for (final ion in WaterIon.values) ion: _read(ions[ion]!)},
              measuredGh: _read(baseGh),
              measuredKh: _read(baseKh),
            )
          : WaterComposition.distilled();
      initialComposition = base;
      final custom = mode == WaterCalculationMode.custom;
      final fraction = custom && !ionTargets && mixHardness
          ? (_read(calciumPercent) ??
                    (throw const FormatException('Missing split'))) /
                100
          : null;
      if (isSavedTarget &&
          (_savedTarget?.gh == null || _savedTarget?.kh == null)) {
        missingTarget = true;
      } else if (((custom && (ionTargets || fraction != null)) ||
              _savedIonTarget) &&
          (base[WaterIon.calcium] == null ||
              base[WaterIon.magnesium] == null)) {
        missingMixtureBase = true;
      } else if (mode != WaterCalculationMode.quantities &&
          (base.gh == null || base.kh == null)) {
        missingBase = true;
      } else {
        final target = mode == WaterCalculationMode.quantities
            ? null
            : _target(fraction);
        final grams = target == null
            ? _manualGrams(volume)
            : _adjust(base, target, volume, fraction);
        recipe = WaterRecipe(
          litres: volume,
          calcium: calcium,
          mode: mode,
          base: base,
          grams: grams,
          target: target,
          presetId: mode == WaterCalculationMode.preset && !isSavedTarget
              ? preset.name
              : null,
          ghSource: ghSource,
          khSource: khSource,
          calciumGhFraction: fraction,
          ionTargets: custom && ionTargets,
          availableSalts: availableSalts,
        );
        alternatives = waterAlternatives(recipe!);
        if (previous != null) {
          final index = alternatives.indexWhere(
            (r) => sameWaterDoses(r, previous),
          );
          if (index >= 0) {
            selectedAlternative = index;
            recipe = alternatives[index];
          }
        }
      }
    } on FormatException {
      recipe = null;
    } on ArgumentError {
      recipe = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }
}
