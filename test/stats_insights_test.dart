import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_insights.dart';

import 'helpers/test_database.dart';

final _now = DateTime(2026, 9, 30, 18);

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  test('periods fit the range and keep empty ones', () {
    expect(periodFor(StatsRange.week), StatsPeriod.day);
    expect(periodFor(StatsRange.quarter), StatsPeriod.week);
    expect(periodFor(StatsRange.all), StatsPeriod.month);
    // 30 September 2026 is a Wednesday: its week starts on Monday the 28th.
    expect(periodStart(_now, StatsPeriod.week), DateTime.utc(2026, 9, 28));
    final totals = totalsPerPeriod(
      [(DateTime(2026, 7, 3), 12.0), (DateTime(2026, 9), 8.0)],
      StatsPeriod.month,
      now: _now,
    );
    expect(totals.map((total) => (total.start.month, total.value)), [
      (7, 12.0),
      (8, 0.0),
      (9, 8.0),
    ]);
    expect(
      totalsPerPeriod(const [], StatsPeriod.day, now: _now, from: _now),
      hasLength(1),
    );
  });

  test('a histogram keeps the empty buckets between', () {
    expect(histogram([21, 24, 26, 38], 5), [
      (from: 20, count: 2),
      (from: 25, count: 1),
      (from: 30, count: 0),
      (from: 35, count: 1),
    ]);
    expect(histogram(const [], 5), isEmpty);
  });

  test('ratings by temperature, by brew number and by cost', () async {
    final kenya = await repository.createCoffee(
      name: 'Kenya',
      roaster: 'North',
      initialGrams: 250,
      paidPriceCents: 2000,
      roastDate: '2026-09-01',
    );
    final cheap = await repository.createCoffee(
      name: 'Cheap',
      roaster: 'South',
      initialGrams: 1000,
      paidPriceCents: 2000,
      roastDate: '2026-09-10',
    );
    final unpriced = await repository.createCoffee(name: 'Gift', roaster: 'X');
    final kenyaLot = (await repository.coffeeLots(kenya)).single.id;
    final cheapLot = (await repository.coffeeLots(cheap)).single.id;
    Future<void> brew(
      String coffee,
      String? lot,
      int day, {
      double? rating,
      double? celsius,
    }) async {
      final id = await repository.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 15,
        temperatureC: celsius,
        brewedAt: DateTime(2026, 9, day, 9),
      );
      if (rating != null) {
        await repository.rateBrew(
          id,
          rating: rating,
          notes: null,
          tasting: const BrewTasting(),
        );
      }
    }

    await brew(kenya, kenyaLot, 11, rating: 6, celsius: 92.5);
    await brew(kenya, kenyaLot, 12, rating: 8, celsius: 93);
    await brew(kenya, kenyaLot, 13, rating: 9, celsius: 95);
    await brew(cheap, cheapLot, 14, rating: 7, celsius: 90);
    await brew(cheap, cheapLot, 15);
    await brew(unpriced, null, 16, rating: 9);
    final brews = await database.select(database.brews).get();
    final coffees = await database.select(database.coffees).get();
    final lots = await database.select(database.coffeeLots).get();

    expect(
      ratingByTemperature(
        brews,
      ).map((key, group) => MapEntry(key, (group.count, group.averageRating))),
      {90: (1, 7.0), 92: (2, 7.0), 94: (1, 9.0)},
    );
    final curve = learningCurve(brews, brews);
    expect(curve[1]!.averageRating, closeTo((6 + 7 + 9) / 3, 1e-9));
    expect((curve[2]!.count, curve[3]!.averageRating), (1, 9.0));

    final prices = pricePerKgByCoffee(coffees, lots);
    final values = coffeeValues(brews, coffees, prices);
    final kenyaValue = values.singleWhere((v) => v.coffee.name == 'Kenya');
    // 20 € for 250 g: 1.20 € per 15 g cup.
    expect(kenyaValue.costPerCup, closeTo(1.2, 1e-9));
    expect((kenyaValue.brewCount, kenyaValue.ratedCount), (3, 3));
    expect(kenyaValue.averageRating, closeTo(23 / 3, 1e-9));
    final cheapValue = values.singleWhere((v) => v.coffee.name == 'Cheap');
    expect(cheapValue.costPerCup, closeTo(0.3, 1e-9));
    // Median of 7.67 and 7: the cheap one (7) is below it.
    expect(bestValue(values).map((v) => v.coffee.name), ['Kenya']);

    final bought = purchases(lots, prices);
    expect(bought.map((purchase) => purchase.price), [20.0, 20.0]);
    expect(bought.first.date, DateTime(2026, 9), reason: 'roast date');
    expect(
      purchases(lots, prices, from: DateTime(2026, 9, 5)),
      hasLength(1),
      reason: 'one bag roasted before the 5th',
    );
    final byRoaster = pricePerKgByRoaster(coffees, lots, prices);
    expect(byRoaster.map((r) => (r.roaster, r.pricePerKg.round())), [
      ('North', 80),
      ('South', 20),
    ]);
    expect(
      pricePerKgByRoaster(
        coffees,
        lots,
        prices,
        from: DateTime(2026, 9, 5),
      ).map((r) => r.roaster),
      ['South'],
    );

    // First brews 10 (Kenya, roasted the 1st) and 4 (Cheap) days after
    // roasting; the gift has no bag.
    expect(medianDaysToFirstBrew(brews, brews, lots), 7);

    final averages = styleAverages(brews, (_) => BrewStyle.filter);
    expect(averages, isEmpty, reason: 'no water, yield or time recorded');
  });

  test('typical ratio and time are medians, so a cold brew does not '
      'drag them', () async {
    final coffee = await repository.createCoffee(
      name: 'Kenya',
      roaster: 'North',
      initialGrams: 250,
    );
    final lot = (await repository.coffeeLots(coffee)).single.id;
    for (final (water, seconds) in [
      (250.0, 150),
      (240.0, 180),
      (900.0, 43200),
    ]) {
      await repository.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 15,
        waterGrams: water,
        timeSeconds: seconds,
        brewedAt: DateTime(2026, 9, 10, 9),
      );
    }
    final brews = await database.select(database.brews).get();
    final filter = styleAverages(
      brews,
      (_) => BrewStyle.filter,
    )[BrewStyle.filter]!;
    expect(filter.timeSeconds, 180);
    expect(filter.ratio, closeTo(250 / 15, 0.001));
    expect(filter.times, hasLength(3));
  });
}
