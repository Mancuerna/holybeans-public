import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manual recipe scales all salts while keeping its composition', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.chooseMode(WaterCalculationMode.quantities);
    model.amounts[WaterSalt.calciumChloride]!.text = '0.12';
    final initial = model.recipe!;
    model.litres.text = '5';
    for (final salt in WaterSalt.values) {
      expect(
        model.recipe!.grams[salt],
        closeTo(initial.grams[salt]! * 5, 1e-10),
      );
    }
    for (final ion in WaterIon.values) {
      expect(model.recipe!.result[ion], closeTo(initial.result[ion]!, 1e-10));
    }
    model.litres.text = '1';
    expect(model.recipe!.grams[WaterSalt.calciumChloride], closeTo(.12, 1e-10));
  });

  test('invalid manual dose does not partially scale the other salts', () {
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.chooseMode(WaterCalculationMode.quantities);
    final epsom = model.amounts[WaterSalt.epsom]!.text;
    model.setSalt(WaterSalt.potassiumBicarbonate, true);
    model.amounts[WaterSalt.potassiumBicarbonate]!.text = '-';
    model.litres.text = '5';
    expect(model.recipe, isNull);
    expect(model.amounts[WaterSalt.epsom]!.text, epsom);
    model.amounts[WaterSalt.potassiumBicarbonate]!.text = '0';
    expect(model.recipe, isNotNull);
    expect(
      model.recipe!.grams[WaterSalt.epsom],
      closeTo(double.parse(epsom) * 5, 1e-10),
    );
  });
}
