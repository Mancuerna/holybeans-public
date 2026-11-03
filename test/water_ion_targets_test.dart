import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = WaterComposition(
    ions: {
      WaterIon.calcium: 40.078,
      WaterIon.magnesium: 24.305,
      WaterIon.sodium: 22.989769,
      WaterIon.potassium: 39.0983,
      WaterIon.sulfate: 38.4252,
      WaterIon.chloride: 113.44,
    },
    measuredKh: 100.0869,
  );
  test(
    'derived hardness and mass ratio do not confuse measured GH with ion mass',
    () {
      final water = WaterComposition(
        ions: {WaterIon.calcium: 40.078, WaterIon.magnesium: 24.305},
        measuredGh: 300,
      );
      expect(water.gh, 300);
      expect(water.calculatedGh, closeTo(200.1738, 1e-9));
      expect(water.calciumMagnesiumMassRatio, closeTo(1.648961119111, 1e-9));
      expect(WaterComposition.distilled().calciumMagnesiumMassRatio, isNull);
      expect(
        WaterComposition(ions: {WaterIon.calcium: 5}).calculatedGh,
        isNull,
      );
    },
  );
  test('independent five-salt reference reaches all requested ions', () {
    final grams = adjustWaterToIons(
      base: WaterComposition.distilled(),
      target: target,
      litres: 1,
      calcium: CalciumForm.dihydrate,
      allowed: WaterSalt.values.toSet(),
    );
    for (final (salt, expected) in [
      (WaterSalt.calciumChloride, .14702),
      (WaterSalt.epsom, .098588),
      (WaterSalt.magnesiumChloride, .12198),
      (WaterSalt.sodiumBicarbonate, .08401),
      (WaterSalt.potassiumBicarbonate, .100115),
    ]) {
      expect(grams[salt], closeTo(expected, 1e-6), reason: salt.name);
    }
    final result = waterFromSalts(grams, 1, CalciumForm.dihydrate);
    for (final ion in WaterIon.values.where((i) => target[i] != null)) {
      expect(result[ion], closeTo(target[ion]!, .001), reason: ion.name);
    }
    expect(result.kh, closeTo(100.0869, 1e-8));
    expect(result.gh, closeTo(200.1738, 1e-8));
  });
  test('contradictory secondary targets cannot displace Ca Mg KH', () {
    final impossible = WaterComposition(
      ions: {
        ...target.ions,
        WaterIon.chloride: 0,
        WaterIon.sulfate: 0,
        WaterIon.sodium: 0,
        WaterIon.potassium: 0,
      },
      measuredKh: 100.0869,
    );
    final grams = adjustWaterToIons(
      base: WaterComposition.distilled(),
      target: impossible,
      litres: 5,
      calcium: CalciumForm.anhydrous,
      allowed: WaterSalt.values.toSet(),
    );
    final result = waterFromSalts(grams, 5, CalciumForm.anhydrous);
    expect(result[WaterIon.calcium], closeTo(40.078, 1e-8));
    expect(result[WaterIon.magnesium], closeTo(24.305, 1e-8));
    expect(result.kh, closeTo(100.0869, 1e-8));
    expect(result[WaterIon.chloride], greaterThan(0));
    expect(grams.values.every((g) => g >= 0), isTrue);
  });
  test('missing salt groups and excesses remain in the actual composition', () {
    final base = WaterComposition(
      ions: {...WaterComposition.distilled().ions, WaterIon.calcium: 50},
    );
    final grams = adjustWaterToIons(
      base: base,
      target: target,
      litres: 1,
      calcium: CalciumForm.dihydrate,
      allowed: {WaterSalt.epsom},
    );
    final result = base.add(waterFromSalts(grams, 1, CalciumForm.dihydrate));
    expect(result[WaterIon.calcium], 50);
    expect(result[WaterIon.magnesium], closeTo(24.305, 1e-8));
    expect(result.kh, 0);
    expect(grams[WaterSalt.calciumChloride], 0);
    expect(grams[WaterSalt.sodiumBicarbonate], 0);
    final none = adjustWaterToIons(
      base: base,
      target: target,
      litres: 1,
      calcium: CalciumForm.dihydrate,
      allowed: {},
    );
    expect(none.values.every((g) => g == 0), isTrue);
  });
  test(
    'random starting waters preserve primary deficits and unavailable salts',
    () {
      final random = Random(19102026);
      for (var run = 0; run < 40; run++) {
        final ca = random.nextDouble() * 60;
        final mg = random.nextDouble() * 30;
        final kh = random.nextDouble() * 150;
        final base = WaterComposition(
          ions: {
            ...WaterComposition.distilled().ions,
            WaterIon.calcium: ca,
            WaterIon.magnesium: mg,
            WaterIon.chloride: random.nextDouble() * 80,
          },
          measuredKh: kh,
        );
        final allowed = WaterSalt.values
            .where((s) => random.nextBool())
            .toSet();
        final form = run.isEven ? CalciumForm.anhydrous : CalciumForm.dihydrate;
        final litres = 1 + random.nextDouble() * 9;
        final grams = adjustWaterToIons(
          base: base,
          target: target,
          litres: litres,
          calcium: form,
          allowed: allowed,
        );
        final result = base.add(waterFromSalts(grams, litres, form));
        expect(
          result[WaterIon.calcium],
          closeTo(
            allowed.contains(WaterSalt.calciumChloride) ? max(ca, 40.078) : ca,
            1e-7,
          ),
        );
        expect(
          result[WaterIon.magnesium],
          closeTo(allowed.any((s) => s.index < 2) ? max(mg, 24.305) : mg, 1e-7),
        );
        expect(
          result.kh,
          closeTo(
            allowed.any((s) => s.index >= 3) ? max(kh, 100.0869) : kh,
            1e-7,
          ),
        );
        for (final salt in WaterSalt.values) {
          expect(grams[salt]!.isFinite && grams[salt]! >= 0, isTrue);
          if (!allowed.contains(salt)) expect(grams[salt], 0);
        }
      }
    },
  );

  test('available salts and optional targets survive JSON and reopen', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.chooseMode(WaterCalculationMode.custom);
    model.setSalt(WaterSalt.magnesiumChloride, true);
    model.setSalt(WaterSalt.epsom, false);
    model.targetIons[WaterIon.sodium]!.text = '0';
    final recipe = WaterRecipe.fromJson(model.recipe!.toJson());
    final reopened = WaterCalculatorModel(seed: recipe);
    addTearDown(reopened.dispose);
    expect(reopened.ionTargets, isTrue);
    expect(reopened.availableSalts, model.availableSalts);
    expect(reopened.targetIons[WaterIon.sulfate]!.text, '');
    expect(reopened.targetIons[WaterIon.sodium]!.text, '0');
    expect(reopened.recipe!.toJson(), recipe.toJson());
    final malformed = jsonDecode(recipe.toJson()) as Map<String, dynamic>;
    malformed['availableSalts'] = <String>[];
    expect(
      () => WaterRecipe.fromJson(jsonEncode(malformed)),
      throwsFormatException,
    );
  });
  test('manual doses preserve unknown ions and never use removed salts', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.chooseMode(WaterCalculationMode.quantities);
    model.mineralWater = true;
    model.amounts[WaterSalt.epsom]!.text = '.1';
    expect(model.recipe, isNotNull);
    expect(model.recipe!.result[WaterIon.magnesium], isNull);
    expect(model.recipe!.added[WaterIon.magnesium], greaterThan(0));
    model.setSalt(WaterSalt.epsom, false);
    expect(model.recipe!.grams[WaterSalt.epsom], 0);
    model.setSalt(WaterSalt.epsom, true);
    expect(model.amounts[WaterSalt.epsom]!.text, '0');
  });
  test('old recipe without new fields keeps its GH target and salt access', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.ionTargets = false;
    model.chooseMode(WaterCalculationMode.custom);
    final old = jsonDecode(model.recipe!.toJson()) as Map<String, dynamic>;
    old.remove('availableSalts');
    old.remove('ionTargets');
    final reopened = WaterCalculatorModel(
      seed: WaterRecipe.fromJson(jsonEncode(old)),
    );
    addTearDown(reopened.dispose);
    expect(reopened.ionTargets, isFalse);
    expect(reopened.availableSalts, WaterSalt.values.toSet());
    expect(reopened.recipe!.result.gh, closeTo(80, 1e-8));
  });
}
