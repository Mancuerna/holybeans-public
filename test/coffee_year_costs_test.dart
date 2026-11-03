import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/domain/coffee_year_costs.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/ui/year_review/year_review_data.dart';
import 'package:holybeans/ui/year_review/year_review_stories.dart';

import 'helpers/year_fixture.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);
  CoffeeYear review({
    List<Coffee>? coffees,
    List<CoffeeLot>? lots,
    List<Brew>? brews,
    int year = 2026,
  }) => coffeeYearFromJournal(
    year: year,
    now: now,
    coffees: coffees ?? [yearCoffee('a', paidPriceCents: 1500)],
    lots: lots ?? [yearLot('a')],
    brews: brews ?? [],
    components: [],
    methods: yearMethods,
  );

  test('spending uses purchases, cups use brew dates and actual dose', () {
    final data = review(
      coffees: [
        yearCoffee('a', paidPriceCents: 1500),
        yearCoffee('b', paidPriceCents: 2000),
      ],
      lots: [
        yearLot('a', purchased: '2025-12-31'),
        yearLot('b', coffee: 'b', grams: 1000, purchased: '2026-02-01'),
      ],
      brews: [
        yearBrew('old-coffee', now, dose: 18),
        yearBrew('low', now, coffee: 'b', dose: 15),
        yearBrew('previous-brew', DateTime(2025, 12, 31), dose: 100),
        yearBrew('future-brew', now.add(const Duration(seconds: 1)), dose: 100),
      ],
    );
    expect(data.costs.totalEuros, 20);
    expect(data.costs.monthlyEuros[1], 20);
    expect(data.costs.coffeePrices.single.coffeeId, 'b');
    expect(data.costs.cups.first.brew.id, 'low');
    expect(data.costs.cups.first.euros, closeTo(.3, 1e-10));
    expect(data.costs.cups.last.brew.id, 'old-coffee');
    expect(data.costs.cups.last.euros, closeTo(1.08, 1e-10));
    expect(data.costs.brewCount, 2);
  });

  test(
    'total quantity allocates price once, independent of remaining stock',
    () {
      final coffees = [yearCoffee('a', paidPriceCents: 3000, archived: true)];
      final lots = [
        yearLot('one', purchased: '2025-12-31'),
        yearLot('two', grams: 500, purchased: '2026-03-01'),
        yearLot('empty', grams: 0),
      ];
      final data = review(coffees: coffees, lots: lots);
      expect(data.costs.totalEuros, 20);
      expect(data.costs.monthlyEuros[2], 20);
      expect(data.costs.coffeePrices.single.eurosPerKg, 40);
      expect(data.costs.purchasedCoffees, 1);
      final prices = pricePerKgByCoffee(coffees, lots);
      final stats = purchases(lots, prices, from: DateTime(2026));
      expect(
        data.costs.totalEuros,
        stats.fold<double>(0, (n, p) => n + p.price),
      );
      expect(
        review(coffees: coffees, lots: lots, year: 2025).costs.totalEuros,
        10,
      );
    },
  );

  test('coffee extremes compare per kilo rather than total amount paid', () {
    final data = review(
      coffees: [
        yearCoffee('a', paidPriceCents: 1000),
        yearCoffee('b', paidPriceCents: 3000),
      ],
      lots: [
        yearLot('a', grams: 50),
        yearLot('b', coffee: 'b', grams: 1000),
      ],
    );
    expect(data.costs.coffeePrices.first.coffeeId, 'b');
    expect(data.costs.coffeePrices.last.coffeeId, 'a');
    expect(data.costs.totalEuros, 40);
  });

  test('unknown or invalid costs stay unknown, explicit zero counts', () {
    final data = review(
      coffees: [
        yearCoffee('a', paidPriceCents: 0),
        yearCoffee('unknown'),
        yearCoffee('weight', paidPriceCents: 1200),
        yearCoffee('invalid', paidPriceCents: -50),
      ],
      lots: [
        yearLot('a'),
        yearLot('unknown', coffee: 'unknown'),
        yearLot('weight', coffee: 'weight', grams: null),
        yearLot('invalid', coffee: 'invalid'),
      ],
      brews: [
        yearBrew('free', now, dose: 15),
        yearBrew('missing-dose', now),
        yearBrew('bad-dose', now, dose: -1),
        yearBrew('infinite', now, dose: double.infinity),
        yearBrew('unknown', now, coffee: 'unknown', dose: 15),
      ],
    );
    expect(data.costs.purchasedCoffees, 4);
    expect(data.costs.costedCoffees, 1);
    expect(data.costs.totalEuros, 0);
    expect(data.costs.cups.single.brew.id, 'free');
    expect(data.costs.cups.single.euros, 0);
    expect(storiesFor(data), contains(YearStory.spending));
    expect(review(coffees: [yearCoffee('a')]).costs.costedCoffees, 0);
    for (final grams in [double.nan, double.infinity, -1.0]) {
      expect(review(lots: [yearLot('a', grams: grams)]).costs.costedCoffees, 0);
    }
  });

  test('fallback dates are disclosed and future purchases excluded', () {
    final data = review(
      coffees: [
        for (final id in ['a', 'b', 'c', 'd'])
          yearCoffee(id, paidPriceCents: 1000),
      ],
      lots: [
        yearLot('a', purchased: null, roasted: '2026-02-01'),
        yearLot('b', coffee: 'b', purchased: null, added: DateTime(2026, 4)),
        yearLot('c', coffee: 'c', purchased: '2026-12-01'),
        yearLot('d', coffee: 'd'),
      ],
    );
    expect(data.costs.totalEuros, 30);
    expect(data.costs.monthlyEuros[0], 10);
    expect(data.costs.monthlyEuros[1], 10);
    expect(data.costs.monthlyEuros[3], 10);
    expect(data.costs.monthlyEuros[11], 0);
    expect(data.costs.estimatedDateCoffees, 2);
    expect(data.costs.purchasedCoffees, 3);
  });

  test('ties match displayed cents with stable coffee and brew identities', () {
    final data = review(
      coffees: [
        yearCoffee('b', paidPriceCents: 1000),
        yearCoffee('a', paidPriceCents: 1000),
      ],
      lots: [
        yearLot('b', coffee: 'b'),
        yearLot('a'),
      ],
      brews: [yearBrew('b', now, dose: 15.01), yearBrew('a', now, dose: 15)],
    );
    expect(data.costs.coffeePrices.first.coffeeId, 'a');
    expect(data.costs.coffeeTies(data.costs.coffeePrices.first), 2);
    expect(data.costs.cups.first.brew.id, 'a');
    expect(data.costs.cupTies(data.costs.cups.first), 2);
    expect(CoffeeYearCosts.cents(data.costs.cups.last.euros), 60);
  });

  test('years with purchases but no brews have spending stories and entry', () {
    final lots = [yearLot('a', purchased: '2023-01-01')];
    final data = review(lots: lots, year: 2023);
    expect(coffeeYears(yearJournalDates([], lots), now), [2023]);
    expect(
      seasonalCoffeeYear(yearJournalDates([], lots), DateTime(2023, 12, 25)),
      2023,
    );
    expect(
      coffeeYears(yearJournalDates([], [yearLot('zero', grams: 0)]), now),
      isEmpty,
    );
    expect(data.count, 0);
    expect(storiesFor(data), [
      YearStory.intro,
      YearStory.expensiveCoffee,
      YearStory.cheapCoffee,
      YearStory.spending,
    ]);
  });
}
