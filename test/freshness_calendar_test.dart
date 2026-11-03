import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/freshness_calendar_data.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/freshness_calendar.dart';

CalendarLot lot(
  String id, {
  DateTime? roast,
  DateTime? opened,
  int pause = 0,
  bool frozen = false,
  double? grams = 100,
  int? rest,
}) => CalendarLot(
  id: id,
  coffeeId: 'c',
  coffeeName: 'Coffee',
  roaster: 'R',
  grams: grams,
  roastDate: roast,
  openedDate: opened,
  frozenPauseDays: pause,
  frozen: frozen,
  roastLevel: 'medium',
  restDays: rest,
);

void main() {
  test('one coffee can have lots in different phases on the same day', () {
    final day = CalendarDay(
      [
        lot('new', roast: DateTime(2026, 11)),
        lot('ready', roast: DateTime(2026, 10, 20)),
        lot('old', roast: DateTime(2026, 7)),
        lot('unknown'),
        lot('future', roast: DateTime(2026, 12)),
        lot('empty', roast: DateTime(2026, 7), grams: 0),
      ],
      DateTime(2026, 11),
      BrewStyle.filter,
    );
    expect(day.phases[FreshnessPhase.degassing]!.single.id, 'new');
    expect(day.phases[FreshnessPhase.prime]!.single.id, 'ready');
    expect(day.phases[FreshnessPhase.stale]!.single.id, 'old');
    expect(day.unknown.map((l) => l.id), ['unknown', 'future']);
  });

  test(
    'style, rest override, opening and thawed pause use existing windows',
    () {
      final roast = DateTime(2026, 10);
      final sample = lot('c', roast: roast);
      final filter = freshnessWindow(
        roastLevel: 'medium',
        style: BrewStyle.filter,
      );
      final espresso = freshnessWindow(
        roastLevel: 'medium',
        style: BrewStyle.espresso,
      );
      expect(filter.primeStart, lessThan(espresso.primeStart));
      final date = DateTime(2026, 10, 1 + filter.primeStart);
      expect(sample.phaseOn(date, BrewStyle.filter), FreshnessPhase.prime);
      expect(
        sample.phaseOn(date, BrewStyle.espresso),
        FreshnessPhase.degassing,
      );
      for (final style in BrewStyle.values) {
        for (var day = 0; day < 100; day++) {
          final at = DateTime(2026, 10, 1 + day);
          final opened = DateTime(2026, 10, 4);
          final entry = lot(
            'p',
            roast: roast,
            opened: opened,
            pause: 10,
            rest: 20,
          );
          final age = effectiveRoastAge(
            roast,
            at,
            frozenPauseDays: 10,
            openedDate: opened,
          )!;
          expect(
            entry.phaseOn(at, style),
            freshnessWindow(
              roastLevel: 'medium',
              style: style,
              restDays: 20,
            ).phaseAt(age),
          );
        }
      }
    },
  );

  test('frozen lots never enter a future phase; unknown stock is retained', () {
    final entries = [
      lot('frozen', roast: DateTime(2026), frozen: true),
      lot('unknown-stock', roast: DateTime(2026, 10, 20), grams: null),
    ];
    for (final date in [DateTime(2026, 11), DateTime(2027)]) {
      final day = CalendarDay(entries, date, BrewStyle.filter);
      expect(day.frozen.single.id, 'frozen');
      expect(day.phases.values.expand((l) => l).single.id, 'unknown-stock');
    }
  });

  test('calendar adapter separates available and frozen, excludes archives and overdraw', () {
    Coffee coffee(String id, {bool archived = false}) => Coffee(
      id: id,
      name: id,
      roaster: 'R',
      isFavorite: false,
      isDecaf: false,
      createdAtMs: 0,
      updatedAtMs: 0,
      archivedAtMs: archived ? 1 : null,
    );
    CoffeeLot row(
      String id,
      String coffeeId, {
      double? grams,
      double? overdraw,
      bool archived = false,
    }) => CoffeeLot(
      id: id,
      coffeeId: coffeeId,
      remainingGrams: grams,
      overdrawGrams: overdraw,
      roastDate: '2026-10-20',
      createdAtMs: 0,
      updatedAtMs: 0,
      archivedAtMs: archived ? 1 : null,
    );
    FrozenPortion portion(String id, String lotId, double grams) =>
        FrozenPortion(
          id: id,
          lotId: lotId,
          label: id,
          frozenDate: '2026-10-25',
          initialGrams: grams,
          remainingGrams: grams,
          createdAtMs: 0,
          updatedAtMs: 0,
        );
    final data = JournalData(
      coffees: [
        coffee('active'),
        coffee('archived', archived: true),
        coffee('no-lots'),
      ],
      brews: [],
      components: [],
      lots: [
        row('mixed', 'active', grams: 100, overdraw: 20),
        row('empty', 'active', grams: 10, overdraw: 20),
        row('unknown', 'active'),
        row('archived-lot', 'active', grams: 100, archived: true),
        row('archived-coffee', 'archived', grams: 100),
      ],
    );
    final entries = calendarLots(data, [
      portion('p', 'mixed', 30),
      portion('p2', 'mixed', 20),
      portion('gone', 'mixed', 0),
      portion('hidden', 'archived-lot', 50),
    ]);
    expect(entries.map((l) => l.id).toSet(), {
      'mixed',
      'frozen:mixed',
      'unknown',
      'no-lots',
    });
    expect(entries.singleWhere((l) => l.id == 'mixed').grams, 80);
    expect(entries.singleWhere((l) => l.frozen).grams, 50);
    expect(entries.singleWhere((l) => l.id == 'unknown').grams, isNull);
    expect(entries.singleWhere((l) => l.id == 'no-lots').roastDate, isNull);
  });
}
