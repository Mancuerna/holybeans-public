import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/ui/year_review/year_review_data.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';

import 'helpers/year_fixture.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);
  CoffeeYear review(
    List<Brew> brews, {
    int year = 2026,
    List<Coffee>? coffees,
    List<CoffeeComponent> components = yearComponents,
  }) => coffeeYearFromJournal(
    year: year,
    now: now,
    brews: brews,
    coffees: coffees ?? [yearCoffee('a')],
    components: components,
    methods: yearMethods,
  );
  test('calendar dates include archived/imported entries, exclude future', () {
    final data = review([
      yearBrew('before', DateTime(2025, 12, 31, 23, 59)),
      yearBrew('start', DateTime(2026), archived: true),
      yearBrew('same-day', DateTime(2026, 1, 1, 23)),
      yearBrew('now', now),
      yearBrew('future', now.add(const Duration(seconds: 1))),
      yearBrew('next', DateTime(2027)),
    ]);
    expect(data.entries.map((e) => e.id), ['start', 'same-day', 'now']);
    expect(data.activeDays, 2);
    expect(data.monthlyBrews[0], 2);
    expect(data.monthlyBrews[9], 1);
    expect(data.isPartial, isTrue);
    expect(
      review([yearBrew('old', DateTime(2025, 5))], year: 2025).isPartial,
      isFalse,
    );
  });
  test(
    'local New Year boundary uses local preparation date, not import date',
    () {
      final boundary = DateTime(2026);
      expect(
        review([
          yearBrew('old', boundary.subtract(const Duration(milliseconds: 1))),
          yearBrew('new', boundary),
        ]).count,
        1,
      );
    },
  );
  test(
    'origin aliases and repeated blend components count once per coffee',
    () {
      final data = review(
        [
          yearBrew('1', now),
          yearBrew('2', now),
          yearBrew('3', now, coffee: 'b'),
        ],
        coffees: [yearCoffee('a'), yearCoffee('b')],
        components: const [
          CoffeeComponent(
            id: '1',
            coffeeId: 'a',
            position: 0,
            country: 'Etiopía',
          ),
          CoffeeComponent(
            id: '2',
            coffeeId: 'a',
            position: 1,
            country: 'Ethiopia',
          ),
          CoffeeComponent(
            id: '3',
            coffeeId: 'a',
            position: 2,
            country: 'Colombia',
          ),
          CoffeeComponent(id: '4', coffeeId: 'b', position: 0, country: ' '),
        ],
      );
      expect(data.countries, hasLength(2));
      expect(data.countries.map((c) => c.count), [1, 1]);
      expect(data.coffeesWithOrigin, 1);
      expect(data.coffeeCount, 2);
    },
  );
  test(
    'unknown doses and ratings stay unknown, valid zero rating is retained',
    () {
      final data = review([
        yearBrew('a', now, dose: 18, rating: 0),
        yearBrew('b', now, dose: -1, rating: double.nan),
        yearBrew('c', now, dose: double.infinity, rating: 12),
        yearBrew('d', now),
      ]);
      expect(data.doseGrams, 18);
      expect(data.knownDoses, 1);
      expect(data.rated.map((b) => b.id), ['a']);
    },
  );
  test('methods follow identity after renaming and roasters ignore casing', () {
    final data = review(
      [
        yearBrew('a', now, method: 'Old V60'),
        yearBrew('b', now, coffee: 'b'),
        yearBrew('c', now, methodId: 'another'),
      ],
      coffees: [
        yearCoffee('a', roaster: ' DAK '),
        yearCoffee('b', roaster: 'dak'),
      ],
    );
    expect(data.methodRanks, hasLength(2));
    expect(data.methodRanks.first.name, 'V60');
    expect(data.methodRanks.first.count, 2);
    expect(data.roasters.single.count, 3);
  });
  test('ties and exploration use distinct coffees, not volume', () {
    final data = review(
      [
        yearBrew('a', DateTime(2026), rating: 9),
        yearBrew('b', DateTime(2026, 1, 2), rating: 9),
        yearBrew('c', DateTime(2026, 2)),
        yearBrew('d', DateTime(2026, 2), coffee: 'b'),
      ],
      coffees: [yearCoffee('a'), yearCoffee('b')],
    );
    expect(data.topRatingTies, 2);
    expect(data.explorerMonth, 2);
    expect(data.explorerTie, isFalse);
    expect(data.coffeeRanks.first.count, 3);
  });
  test('missing fields omit stories rather than inventing favourites', () {
    final data = review(
      [yearBrew('a', now, methodId: null, method: '')],
      coffees: [yearCoffee('a', roaster: '')],
      components: [],
    );
    expect(storiesFor(data), [
      YearStory.intro,
      YearStory.returning,
      YearStory.rhythm,
      YearStory.finalCard,
    ]);
    expect(storiesFor(review([])), [YearStory.intro]);
  });
  test(
    'seasonal invite opens Dec 25 through Jan 31, only for populated year',
    () {
      final brews = [
        yearBrew('a', DateTime(2026)),
        yearBrew('old', DateTime(2024)),
        yearBrew('future', DateTime(2030)),
      ];
      expect(
        seasonalCoffeeYear(
          brews.map((brew) => brew.brewedAtMs),
          DateTime(2026, 12, 24, 23, 59),
        ),
        isNull,
      );
      expect(
        seasonalCoffeeYear(
          brews.map((brew) => brew.brewedAtMs),
          DateTime(2026, 12, 25),
        ),
        2026,
      );
      expect(
        seasonalCoffeeYear(
          brews.map((brew) => brew.brewedAtMs),
          DateTime(2027, 1, 31, 23, 59),
        ),
        2026,
      );
      expect(
        seasonalCoffeeYear(
          brews.map((brew) => brew.brewedAtMs),
          DateTime(2027, 2),
        ),
        isNull,
      );
      expect(seasonalCoffeeYear([], DateTime(2026, 12, 25)), isNull);
      expect(coffeeYears(brews.map((brew) => brew.brewedAtMs), now), [
        2026,
        2024,
      ]);
    },
  );
}
