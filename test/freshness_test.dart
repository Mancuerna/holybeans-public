import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/freshness.dart';

void main() {
  test('degassing curves follow the published fits', () {
    final medium = degassingCurves['medium']!;
    expect(medium.releasedBy(0), 0);
    // λ is the time to release 1 − 1/e ≈ 63 % of the gas.
    expect(medium.releasedBy(medium.scaleDays), closeTo(0.632, 0.001));
    expect(medium.dayReleasing(medium.releasedBy(12)), closeTo(12, 1e-9));
    // Darker roasts release their gas sooner.
    expect(
      degassingCurves['dark']!.releasedBy(7),
      greaterThan(medium.releasedBy(7)),
    );
    expect(
      degassingCurves['ultra_light']!.releasedBy(7),
      lessThan(degassingCurves['light']!.releasedBy(7)),
    );
  });

  test('windows follow roast level and style', () {
    FreshnessWindow window(String? level, BrewStyle style) =>
        freshnessWindow(roastLevel: level, style: style);
    expect(
      window('medium', BrewStyle.filter),
      const FreshnessWindow(
        primeStart: 5,
        primeEnd: 16,
        goodUntil: 22,
        agingUntil: 34,
      ),
    );
    expect(window('medium', BrewStyle.espresso).primeStart, 8);
    expect(window('dark', BrewStyle.filter).primeStart, 4);
    expect(window('light', BrewStyle.espresso).primeStart, 13);
    // Omni sits between medium and light, for filter and espresso alike.
    for (final style in BrewStyle.values) {
      final omni = window('omni', style).primeStart;
      expect(omni, greaterThan(window('medium', style).primeStart));
      expect(omni, lessThan(window('light', style).primeStart));
    }
    expect(window(null, BrewStyle.filter), window('medium', BrewStyle.filter));
    // The ultra-light fit is extrapolated past a month, so it is capped.
    expect(window('ultra_light', BrewStyle.filter).agingUntil, 90);
  });

  test('the roaster rest sets the pace of the curve', () {
    final filter = freshnessWindow(
      roastLevel: 'medium',
      style: BrewStyle.filter,
      restDays: 10,
    );
    final espresso = freshnessWindow(
      roastLevel: 'medium',
      style: BrewStyle.espresso,
      restDays: 10,
    );
    expect(filter.primeStart, 10);
    // Twice as slow as the default medium curve: everything stretches.
    expect(filter.primeEnd, 32);
    expect(espresso.primeStart, 16);

    // Very long rests shift the dates instead of stretching them further.
    final long = freshnessWindow(
      roastLevel: 'medium',
      style: BrewStyle.filter,
      restDays: 60,
    );
    expect(long.primeStart, 60);
    expect(long.primeEnd - long.primeStart, lessThan(20));
  });

  test('phases and days left', () {
    const window = FreshnessWindow(
      primeStart: 10,
      primeEnd: 30,
      goodUntil: 42,
      agingUntil: 60,
    );
    expect(window.phaseAt(3), FreshnessPhase.degassing);
    expect(window.daysLeftInPhase(3), 7);
    expect(window.phaseAt(10), FreshnessPhase.prime);
    expect(window.daysLeftInPhase(30), 1);
    expect(window.phaseAt(31), FreshnessPhase.good);
    expect(window.phaseAt(60), FreshnessPhase.aging);
    expect(window.phaseAt(61), FreshnessPhase.stale);
    expect(window.daysLeftInPhase(61), isNull);
  });

  test('age skips frozen days and counts an open bag faster', () {
    final roast = DateTime(2026, 9);
    expect(effectiveRoastAge(roast, DateTime(2026, 9, 30, 23)), 29);
    expect(
      effectiveRoastAge(roast, DateTime(2026, 9, 30), frozenPauseDays: 20),
      9,
    );
    // Opened on day 20: the last 9 days count 1.7 times.
    expect(
      effectiveRoastAge(
        roast,
        DateTime(2026, 9, 30),
        openedDate: DateTime(2026, 9, 21),
      ),
      35,
    );
    expect(effectiveRoastAge(roast, DateTime(2026, 8, 30)), isNull);
  });

  test('sweet spot follows the smoothed ratings', () {
    RatedBrewSample s(int day, double rating, [double weight = 1]) =>
        RatedBrewSample(day: day, rating: rating, weight: weight);
    final spot = findSweetSpot([
      s(4, 5),
      s(6, 5.5),
      s(12, 7.5),
      s(14, 8.5),
      s(15, 8.5),
      s(17, 8),
      s(25, 6),
      s(27, 5.5),
    ]);
    expect(spot, isNotNull);
    expect(spot!.startDay, lessThanOrEqualTo(15));
    expect(spot.endDay, greaterThanOrEqualTo(15));
    expect(spot.startDay, greaterThanOrEqualTo(11));
    expect(spot.endDay, lessThanOrEqualTo(20));
    expect(spot.averageRating, greaterThan(7.8));
    expect(spot.brewCount, greaterThanOrEqualTo(3));

    // Too few brews, too short a span, flat ratings or unrelated coffees
    // give no sweet spot.
    expect(findSweetSpot([s(5, 5), s(10, 9), s(20, 6), s(30, 5)]), isNull);
    expect(
      findSweetSpot([
        for (final day in [10, 11, 12, 13, 14]) s(day, 9),
      ]),
      isNull,
    );
    expect(
      findSweetSpot([
        for (final day in [2, 4, 6, 12, 14, 16]) s(day, 7),
      ]),
      isNull,
    );
    expect(
      findSweetSpot([
        for (final day in [4, 6, 12, 14, 15, 17, 25, 27]) s(day, 9, 0),
      ]),
      isNull,
    );
  });

  test('similarity weights', () {
    expect(
      sweetSpotWeight(
        sameCoffee: true,
        sameRoastLevel: false,
        sameRoaster: false,
      ),
      1,
    );
    expect(
      sweetSpotWeight(
        sameCoffee: false,
        sameRoastLevel: true,
        sameRoaster: true,
      ),
      0.5,
    );
    expect(
      sweetSpotWeight(
        sameCoffee: false,
        sameRoastLevel: true,
        sameRoaster: false,
      ),
      0.25,
    );
    expect(
      sweetSpotWeight(
        sameCoffee: false,
        sameRoastLevel: false,
        sameRoaster: true,
      ),
      0,
    );
  });

  test('the first brew from a bag marks it opened', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffeeWithComponents(
      name: 'Opened',
      roaster: 'Roaster',
      components: const [],
      initialGrams: 250,
    );
    final lotId = (await repository.coffeeLots(coffeeId)).single.id;
    Future<String?> opened() async =>
        (await repository.coffeeLots(coffeeId)).single.openedDate;
    expect(await opened(), isNull);

    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lotId,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: DateTime(2026, 9, 20, 8),
    );
    expect(await opened(), '2026-09-20');
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lotId,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: DateTime(2026, 9, 25, 8),
    );
    expect(await opened(), '2026-09-20');
    // Logging an older brew later moves the opening back.
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lotId,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: DateTime(2026, 9, 18, 8),
    );
    expect(await opened(), '2026-09-18');
  });
}
