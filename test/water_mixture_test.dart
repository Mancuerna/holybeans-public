import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final form in CalciumForm.values) {
    for (final salt in [WaterSalt.epsom, WaterSalt.magnesiumChloride]) {
      for (final fraction in [0.0, .25, .5, 1.0]) {
        test('$form $salt $fraction reaches GH, split and scales doses', () {
          final target = customWaterTarget(
            80,
            40,
            salt,
            WaterSalt.sodiumBicarbonate,
            form,
            calciumGhFraction: fraction,
          );
          final grams = adjustWaterMixture(
            base: WaterComposition.distilled(),
            target: target,
            litres: 5,
            calcium: form,
            magnesiumSource: salt,
            khSource: WaterSalt.sodiumBicarbonate,
          );
          final result = waterFromSalts(grams, 5, form);
          expect(result.gh, closeTo(80, 1e-8));
          expect(result.kh, closeTo(40, 1e-8));
          expect(
            result[WaterIon.calcium],
            closeTo(80 * fraction * 40.078 / calciumCarbonateMass, 1e-8),
          );
          expect(
            result[WaterIon.magnesium],
            closeTo(80 * (1 - fraction) * 24.305 / calciumCarbonateMass, 1e-8),
          );
          for (final ion in WaterIon.values) {
            expect(result[ion], closeTo(target[ion]!, 1e-8));
          }
        });
      }
    }
  }
  test(
    'known bottle ions reach split despite unrelated chloride and sulfate',
    () {
      final target = customWaterTarget(
        80,
        40,
        WaterSalt.epsom,
        WaterSalt.sodiumBicarbonate,
        CalciumForm.dihydrate,
        calciumGhFraction: .5,
      );
      final base = WaterComposition(
        ions: {
          ...WaterComposition.distilled().ions,
          WaterIon.calcium: 5,
          WaterIon.magnesium: 2,
          WaterIon.chloride: 100,
          WaterIon.sulfate: 100,
        },
      );
      final grams = adjustWaterMixture(
        base: base,
        target: target,
        litres: 1,
        calcium: CalciumForm.dihydrate,
        magnesiumSource: WaterSalt.epsom,
        khSource: WaterSalt.sodiumBicarbonate,
      );
      final result = base.add(waterFromSalts(grams, 1, CalciumForm.dihydrate));
      expect(result.gh, closeTo(80, 1e-8));
      expect(
        result[WaterIon.calcium],
        closeTo(target[WaterIon.calcium]!, 1e-8),
      );
      expect(
        result[WaterIon.magnesium],
        closeTo(target[WaterIon.magnesium]!, 1e-8),
      );
      expect(result[WaterIon.chloride], greaterThanOrEqualTo(100));
    },
  );
  test('excess calcium keeps GH priority without removing minerals', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.ionTargets = false;
    model.mixHardness = true;
    model.chooseMode(WaterCalculationMode.custom);
    model.mineralWater = true;
    model.ions[WaterIon.calcium]!.text = '20';
    model.ions[WaterIon.magnesium]!.text = '0';
    model.baseKh.text = '0';
    expect(model.recipe!.result.gh, closeTo(80, 1e-6));
    expect(model.recipe!.result[WaterIon.calcium], greaterThanOrEqualTo(20));
    expect(model.recipe!.grams.values.every((g) => g >= 0), isTrue);
  });
  test(
    'mixture survives JSON and reopening, old recipes stay single-source',
    () {
      final model = WaterCalculatorModel();
      addTearDown(model.dispose);
      model.ionTargets = false;
      model.mixHardness = true;
      model.ghSource = WaterSalt.magnesiumChloride;
      model.calcium = CalciumForm.anhydrous;
      model.calciumPercent.text = '35';
      model.chooseMode(WaterCalculationMode.custom);
      final recipe = WaterRecipe.fromJson(model.recipe!.toJson());
      final reopened = WaterCalculatorModel(seed: recipe);
      addTearDown(reopened.dispose);
      expect(reopened.mixHardness, isTrue);
      expect(reopened.calciumPercent.text, '35');
      expect(reopened.recipe!.grams, model.recipe!.grams);
      final old = jsonDecode(recipe.toJson()) as Map<String, dynamic>;
      old.remove('calciumGhFraction');
      expect(WaterRecipe.fromJson(jsonEncode(old)).calciumGhFraction, isNull);
      for (final invalid in [-1, 1.1, 'half']) {
        old['calciumGhFraction'] = invalid;
        expect(
          () => WaterRecipe.fromJson(jsonEncode(old)),
          throwsFormatException,
        );
      }
    },
  );
  test('unknown bottle split and invalid percentage block mixture only', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.ionTargets = false;
    model.mixHardness = true;
    model.chooseMode(WaterCalculationMode.custom);
    model.calciumPercent.text = '101';
    expect(model.recipe, isNull);
    model.calciumPercent.text = '50';
    model.mineralWater = true;
    model.baseGh.text = '20';
    model.baseKh.text = '10';
    expect(model.missingMixtureBase, isTrue);
    expect(model.recipe, isNull);
    model.mixHardness = false;
    model.recalculate();
    expect(model.recipe, isNotNull);
  });
}
