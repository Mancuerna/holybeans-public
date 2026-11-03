import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Holy Water retains the published potassium recipe and all ions', () {
    final w = WaterPreset.holyWater.composition;
    expect(w.gh, closeTo(61.72, .02));
    expect(w.kh, closeTo(22.99, .02));
    expect(w[WaterIon.magnesium], closeTo(14.99, .01));
    expect(w[WaterIon.potassium], closeTo(17.96, .01));
    expect(w[WaterIon.sulfate], closeTo(59.24, .01));
    expect(w[WaterIon.bicarbonate], closeTo(28.04, .01));
    expect(w[WaterIon.calcium], 0);
    expect(w[WaterIon.sodium], 0);
    expect(w[WaterIon.chloride], 0);
  });

  test(
    'Rao Lotus reproduces each mineral contribution, not just GH and KH',
    () {
      for (final form in CalciumForm.values) {
        final grams = WaterPreset.raoLotus.gramsPerLitre(form);
        final w = waterFromSalts(grams, 1, form);
        expect(w.gh, closeTo(72.3, 1e-9));
        expect(w.kh, closeTo(20.1, 1e-9));
        expect(w[WaterIon.magnesium], closeTo(7.795, .001));
        expect(w[WaterIon.calcium], closeTo(16.097, .001));
        expect(w[WaterIon.sodium], closeTo(5.559, .001));
        expect(w[WaterIon.potassium], closeTo(6.250, .001));
        expect(w[WaterIon.chloride], closeTo(51.216, .001));
        expect(w[WaterIon.bicarbonate], closeTo(24.507, .001));
        expect(w[WaterIon.sulfate], 0);
        expect(grams[WaterSalt.epsom], isNull);
      }
    },
  );

  test('GWO adaptation scales the published 5L masses and omits sea salt', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.choosePreset(WaterPreset.gwoNoSeaSalt);
    model.litres.text = '5';
    expect(model.recipe!.grams[WaterSalt.epsom], closeTo(.332, 1e-12));
    expect(
      model.recipe!.grams[WaterSalt.sodiumBicarbonate],
      closeTo(.050, 1e-12),
    );
    expect(model.recipe!.result.gh, closeTo(26.963, .001));
    expect(model.recipe!.result.kh, closeTo(5.957, .001));
    expect(model.recipe!.result[WaterIon.chloride], 0);
  });

  test('BH adaptations reproduce their documented targets', () {
    for (final (preset, gh, kh) in [
      (WaterPreset.scaBh, 68.6, 40.1),
      (WaterPreset.melbourneBh, 23.7, 11.5),
      (WaterPreset.budapestBh, 51.2, 40.1),
      (WaterPreset.raoBh, 75.7, 50.1),
    ]) {
      expect(preset.composition.gh, closeTo(gh, 1e-9));
      expect(preset.composition.kh, closeTo(kh, 1e-9));
      expect(preset.composition[WaterIon.calcium], 0);
      expect(preset.composition[WaterIon.potassium], 0);
    }
  });

  test(
    'every preset reopens its stored composition and scales after reopening',
    () {
      for (final preset in WaterPreset.values) {
        final original = WaterCalculatorModel()..choosePreset(preset);
        addTearDown(original.dispose);
        final restored = WaterCalculatorModel(
          seed: WaterRecipe.fromJson(original.recipe!.toJson()),
        );
        addTearDown(restored.dispose);
        expect(restored.preset, preset);
        restored.litres.text = '5';
        for (final ion in WaterIon.values) {
          expect(
            restored.recipe!.result[ion],
            closeTo(original.recipe!.result[ion]!, .001),
            reason: '${preset.name}: $ion',
          );
        }
      }
    },
  );
}
