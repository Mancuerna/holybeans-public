import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_comparison.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/shot_curve.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repository;
  late String coffee;
  setUp(() async {
    db = memoryDatabase();
    repository = JournalRepository(db);
    coffee = await repository.createCoffee(name: 'Comparison', roaster: 'Test');
  });
  tearDown(() => db.close());

  Future<Brew> brew({
    String method = 'V60',
    double? dose,
    double? water,
    double? output,
    double? tds,
    String? setting,
  }) async {
    final id = await repository.createBrew(
      coffeeId: coffee,
      methodName: method,
      doseGrams: dose,
      waterGrams: water,
      beverageGrams: output,
      tdsPercent: tds,
      grindSetting: setting,
    );
    return (await db.select(db.brews).get()).singleWhere(
      (brew) => brew.id == id,
    );
  }

  test('filter uses water for ratio and beverage for EY; differences are B minus A', () async {
    final a = await brew(dose: 20, water: 300, output: 250, tds: 1.2);
    final b = await brew(dose: 20, water: 320, output: 280, tds: 1.4);
    final comparison = BrewComparison(a, b);
    expect(
      (comparison.ratioA, comparison.ratioB, comparison.ratioDifference),
      (15, 16, 1),
    );
    final ey = comparison.numbers.singleWhere(
      (row) => row.parameter == BrewParameter.ey,
    );
    expect(ey.a, 15);
    expect(ey.b, closeTo(19.6, .0001));
    expect(ey.difference, closeTo(4.6, .0001));
  });

  test(
    'sensory comparison requires complete measurements on both brews',
    () async {
      final a = await brew(dose: 20, water: 300, output: 250, tds: 1.2);
      final b = await brew(dose: 20, water: 320, output: 280, tds: 1.4);
      expect(hasSensoryComparison(a, b), isTrue);
      final missing = await brew(dose: 20, water: 320, output: 280);
      expect(hasSensoryComparison(a, missing), isFalse);
    },
  );

  test(
    'espresso ratios use yield and missing values are never treated as zero',
    () async {
      final a = await brew(
        method: 'Espresso',
        dose: 18,
        output: 36,
        setting: '1.2.3',
      );
      final b = await brew(
        method: 'Espresso',
        dose: 18,
        output: 45,
        setting: '7 clicks',
      );
      final comparison = BrewComparison(a, b);
      expect(
        (comparison.ratioA, comparison.ratioB, comparison.ratioDifference),
        (2, 2.5, .5),
      );
      expect(
        comparison.numbers
            .singleWhere((row) => row.parameter == BrewParameter.tds)
            .difference,
        isNull,
      );
      expect(
        comparison.numbers
            .singleWhere((row) => row.parameter == BrewParameter.ey)
            .a,
        isNull,
      );
      expect((a.grindSetting, b.grindSetting), ('1.2.3', '7 clicks'));
    },
  );

  test('cross style ratios have no numerical difference; missing beverage does not use water for EY', () async {
    final a = await brew(method: 'Named machine', dose: 18, output: 36);
    final b = await brew(dose: 18, water: 288, tds: 1.4);
    final comparison = BrewComparison(
      a,
      b,
      categoryA: 'espresso',
      categoryB: 'pourover',
    );
    expect(comparison.ratioDifference, isNull);
    expect(
      comparison.numbers
          .singleWhere((row) => row.parameter == BrewParameter.ey)
          .b,
      isNull,
    );
  });

  test('only compatible curve units overlay; recorded time offsets and negative weights survive', () {
    final curve = ShotCurve(
      timesMs: [5000, 6000, 7000],
      flow: [1, double.nan, 2],
      weight: [-.2, 4, 8],
      pressure: [1, 4, 9],
    );
    final a = ComparisonCurve(curve, 'g/s');
    final b = ComparisonCurve(curve, 'ml/s');
    expect(canOverlayCurves(a, b, CurveSeries.weight), isTrue);
    expect(canOverlayCurves(a, b, CurveSeries.pressure), isTrue);
    expect(canOverlayCurves(a, b, CurveSeries.flow), isFalse);
    expect(a.samples(CurveSeries.flow), [
      (timeMs: 5000, value: 1.0),
      (timeMs: 7000, value: 2.0),
    ]);
    expect(a.samples(CurveSeries.weight).first, (timeMs: 5000, value: -.2));
  });
}
