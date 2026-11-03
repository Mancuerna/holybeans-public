import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_alternatives.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WaterCalculatorModel model() {
    final m = WaterCalculatorModel();
    addTearDown(m.dispose);
    m.setSalt(WaterSalt.potassiumBicarbonate, true);
    m.setSalt(WaterSalt.magnesiumChloride, true);
    m.chooseMode(WaterCalculationMode.custom);
    return m;
  }

  test('alternatives offer both bicarbonates and magnesium sources', () {
    final m = model();
    for (final salt in [
      WaterSalt.sodiumBicarbonate,
      WaterSalt.potassiumBicarbonate,
      WaterSalt.epsom,
      WaterSalt.magnesiumChloride,
    ]) {
      expect(m.alternatives.any((r) => r.grams[salt]! > 0), isTrue);
    }
    for (final r in m.alternatives.skip(1)) {
      expect(r.result[WaterIon.calcium], closeTo(16, .001));
      expect(r.result[WaterIon.magnesium], closeTo(10, .001));
      expect(r.result.kh, closeTo(40, .001));
    }
    for (var i = 0; i < m.alternatives.length; i++) {
      expect(
        m.alternatives
            .skip(i + 1)
            .any((r) => sameWaterDoses(r, m.alternatives[i])),
        isFalse,
      );
    }
  });

  test(
    'selection scales, survives recipe round trip and excludes removed salts',
    () {
      final m = model();
      final index = m.alternatives.indexWhere(
        (r) =>
            r.grams[WaterSalt.potassiumBicarbonate]! > 0 &&
            r.grams[WaterSalt.sodiumBicarbonate] == 0,
      );
      m.selectAlternative(index);
      final chosen = m.recipe!;
      m.litres.text = '5';
      expect(sameWaterDoses(chosen, m.recipe!), isTrue);
      final reopened = WaterCalculatorModel(
        seed: WaterRecipe.fromJson(m.recipe!.toJson()),
      );
      addTearDown(reopened.dispose);
      expect(sameWaterDoses(m.recipe!, reopened.recipe!), isTrue);
      m.setSalt(WaterSalt.potassiumBicarbonate, false);
      expect(
        m.alternatives.every(
          (r) => r.grams[WaterSalt.potassiumBicarbonate] == 0,
        ),
        isTrue,
      );
      expect(m.recipe!.grams[WaterSalt.potassiumBicarbonate], 0);
      m.chooseMode(WaterCalculationMode.quantities);
      expect(m.alternatives, hasLength(1));
    },
  );

  test('unreachable primary targets do not appear as alternatives', () {
    final m = model();
    m.setSalt(WaterSalt.calciumChloride, false);
    expect(m.alternatives, hasLength(1));
    m.mineralWater = true;
    m.baseKh.text = '80';
    m.ions[WaterIon.calcium]!.text = '30';
    m.ions[WaterIon.magnesium]!.text = '20';
    expect(m.alternatives, hasLength(1));
  });

  test('manual GH stays separate and overrides automatic GH', () {
    final m = model();
    m.mineralWater = true;
    m.baseKh.text = '10';
    m.ions[WaterIon.calcium]!.text = '5';
    m.ions[WaterIon.magnesium]!.text = '2';
    final calculated = m.initialComposition!.calculatedGh;
    expect(m.baseGh.text, isEmpty);
    expect(m.initialComposition!.gh, calculated);
    m.baseGh.text = '50';
    expect(m.initialComposition!.gh, 50);
    expect(m.initialComposition!.calculatedGh, calculated);
    m.baseGh.clear();
    expect(m.initialComposition!.gh, calculated);
  });
}
