import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/brew_parameters.dart';

const a = Brew(
  isPreGround: false,
  isFavorite: false,
  updatedAtMs: 1,
  id: 'a',
  coffeeId: 'coffee',
  methodName: 'Espresso',
  doseGrams: 18,
  beverageGrams: 36,
  brewedAtMs: 1,
  createdAtMs: 1,
);
void main() {
  test('identical brews omit all rows including unknown values', () {
    expect(
      BrewComparison(a, a).differences(preGroundLabel: 'Pre-ground'),
      isEmpty,
    );
  });
  test(
    'recipe differences and results are separated and missing is not zero',
    () {
      const b = Brew(
        isPreGround: false,
        isFavorite: false,
        updatedAtMs: 1,
        id: 'b',
        coffeeId: 'coffee',
        methodName: 'Espresso',
        doseGrams: 18,
        beverageGrams: 45,
        brewedAtMs: 2,
        createdAtMs: 2,
        temperatureC: 0,
        timeSeconds: 30,
        grindSetting: '4.5',
        waterProfileName: 'Rao',
      );
      final rows = BrewComparison(
        a,
        b,
      ).differences(preGroundLabel: 'Pre-ground');
      final temp = rows.singleWhere(
        (r) => r.parameter == BrewParameter.temperature,
      );
      expect((temp.a, temp.b, temp.result), (null, 0, false));
      expect(rows.any((r) => r.parameter == BrewParameter.dose), isFalse);
      expect(
        rows.singleWhere((r) => r.parameter == BrewParameter.ratio).result,
        isTrue,
      );
      expect(
        rows.singleWhere((r) => r.parameter == BrewParameter.time).result,
        isTrue,
      );
      expect(
        rows.singleWhere((r) => r.parameter == BrewParameter.waterProfile).b,
        'Rao',
      );
    },
  );
  test(
    'filter ratio belongs to recipe and mixed styles do not compare ratios',
    () {
      const b = Brew(
        isPreGround: false,
        isFavorite: false,
        updatedAtMs: 1,
        id: 'b',
        coffeeId: 'coffee',
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 288,
        brewedAtMs: 2,
        createdAtMs: 2,
      );
      final rows = BrewComparison(
        b,
        b.copyWith(waterGrams: const Value(300)),
      ).differences(preGroundLabel: 'Pre-ground');
      expect(
        rows.singleWhere((r) => r.parameter == BrewParameter.ratio).result,
        isFalse,
      );
      expect(
        BrewComparison(a, b)
            .differences(preGroundLabel: 'Pre-ground')
            .any((r) => r.parameter == BrewParameter.ratio),
        isFalse,
      );
    },
  );
  test('pre-ground ignores stale grinder setting and rpm', () {
    final pre = a.copyWith(
      isPreGround: true,
      grindSetting: const Value('stale'),
      grindRpm: const Value(100),
    );
    final other = pre.copyWith(
      grindSetting: const Value('other'),
      grindRpm: const Value(200),
    );
    expect(
      BrewComparison(pre, other).differences(preGroundLabel: 'Pre-ground'),
      isEmpty,
    );
  });
}
