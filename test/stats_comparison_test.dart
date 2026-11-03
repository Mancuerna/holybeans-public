import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/stats_comparison.dart';

void main() {
  test('relative change compares with the period before', () {
    expect(relativeChange(118, 100), closeTo(.18, 1e-9));
    expect(relativeChange(50, 100), closeTo(-.5, 1e-9));
    expect(relativeChange(10, 0), isNull);
    expect(relativeChange(null, 3), isNull);
  });

  test('best shot times are the middle half of the well-rated shots', () {
    ({int seconds, double? rating}) shot(int seconds, double? rating) =>
        (seconds: seconds, rating: rating);
    expect(
      bestShotTimes([
        shot(24, 8),
        shot(26, 9),
        shot(28, 8.5),
        shot(30, 8),
        shot(32, 9),
        shot(45, 4),
        shot(18, null),
      ]),
      (from: 26, to: 30),
    );
    expect(bestShotTimes([shot(28, 9), shot(29, 9)]), isNull);
  });

  test(
    'the previous period ends the day before the current one starts',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(name: 'C', roaster: 'R');
      final now = DateTime(2026, 10, 12, 12);
      for (final daysAgo in [0, 6, 7, 13, 14]) {
        await repository.createBrew(
          coffeeId: coffee,
          methodName: 'V60',
          brewedAt: now.subtract(Duration(days: daysAgo)),
        );
      }
      final brews = await database.select(database.brews).get();
      final previous = previousPeriod(
        brews,
        StatsRange.week,
        now,
        brewedAtMs: (brew) => brew.brewedAtMs,
      )!;
      // This week runs from 6 days ago to today; the one before, 7 to 13.
      expect(previous.now, DateTime.utc(2026, 10, 5));
      expect(previous.brews, hasLength(3));
      expect(
        previousPeriod(
          brews,
          StatsRange.all,
          now,
          brewedAtMs: (brew) => brew.brewedAtMs,
        ),
        isNull,
      );
    },
  );
}
