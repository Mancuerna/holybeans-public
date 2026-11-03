import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en'));

  test('espresso uses beverage output and other methods use brew water', () {
    expect(
      formatBrewRatio(
        methodCategory: 'espresso',
        methodName: 'Shot',
        doseGrams: 18,
        waterGrams: 270,
        beverageGrams: 36,
        localeName: 'en',
      ),
      '1:2',
    );
    expect(
      formatBrewRatio(
        methodCategory: 'pourover',
        methodName: 'Espresso named pour over',
        doseGrams: 18,
        waterGrams: 270,
        beverageGrams: 36,
        localeName: 'en',
      ),
      '1:15',
    );
  });

  test('water ratio shortcuts and their targets', () {
    expect(filterRecipeRatio(18, 270), 15);
    expect(filterRecipeRatio(0, 270), isNull);
    expect(filterRecipeRatio(18, double.infinity), isNull);
    expect(brewRatioTargetGrams(doseGrams: 18, ratio: 2.5), 45);
    expect(brewRatioTargetGrams(doseGrams: 18, ratio: 16), 288);
    expect(brewRatioTargetGrams(doseGrams: 0, ratio: 16), isNull);
    expect(brewRatioTargetGrams(doseGrams: 18, ratio: double.infinity), isNull);
  });

  test(
    'legacy espresso names are supported and incomplete recipes omit ratio',
    () {
      expect(
        formatBrewRatio(
          methodCategory: null,
          methodName: 'Espresso',
          doseGrams: 18,
          waterGrams: 270,
          beverageGrams: 38,
          localeName: 'en',
        ),
        '1:2.1',
      );
      expect(
        formatBrewRatio(
          methodCategory: 'espresso',
          methodName: 'Espresso',
          doseGrams: 18,
          waterGrams: 270,
          beverageGrams: null,
          localeName: 'en',
        ),
        isNull,
      );
      expect(
        formatBrewRatio(
          methodCategory: 'pourover',
          methodName: 'V60',
          doseGrams: null,
          waterGrams: 270,
          beverageGrams: 200,
          localeName: 'en',
        ),
        isNull,
      );
    },
  );

  test('a brew sets the espresso target in the slider steps and range', () {
    expect(espressoTargetRatioOf(doseGrams: 15, beverageGrams: 37.1), 2.5);
    expect(espressoTargetRatioOf(doseGrams: 18, beverageGrams: 90), 5.0);
    expect(espressoTargetRatioOf(doseGrams: 18, beverageGrams: 12), 1.0);
    expect(espressoTargetRatioOf(doseGrams: 18), isNull);
    expect(espressoTargetRatioOf(doseGrams: 18, beverageGrams: 180), 10);
    // A filter brew does not aim a shot.
    expect(
      espressoTargetRatioOf(doseGrams: 18.7, beverageGrams: 293.9),
      isNull,
    );
    expect(espressoTargetRatioOf(doseGrams: 0, beverageGrams: 36), isNull);
  });
}
