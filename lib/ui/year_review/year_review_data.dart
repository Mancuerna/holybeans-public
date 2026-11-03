import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/domain/coffee_year_costs.dart';
import 'package:holybeans/domain/stats_insights.dart';

CoffeeYear coffeeYearFromJournal({
  required int year,
  required DateTime now,
  required List<Brew> brews,
  required List<Coffee> coffees,
  required List<CoffeeComponent> components,
  required List<BrewMethod> methods,
  List<CoffeeLot> lots = const [],
}) {
  final prices = pricePerKgByCoffee(coffees, lots);
  // Invalid imported weights must not make an otherwise unknown price usable.
  for (final lot in lots) {
    if (lot.initialGrams == null ||
        !lot.initialGrams!.isFinite ||
        lot.initialGrams! < 0) {
      prices.remove(lot.coffeeId);
    }
  }
  return CoffeeYear(
    year: year,
    now: now,
    brews: [
      for (final brew in brews)
        (
          id: brew.id,
          coffeeId: brew.coffeeId,
          methodId: brew.methodId,
          methodName: brew.methodName,
          doseGrams: brew.doseGrams,
          rating: brew.rating,
          brewedAtMs: brew.brewedAtMs,
        ),
    ],
    coffees: [
      for (final coffee in coffees)
        (id: coffee.id, name: coffee.name, roaster: coffee.roaster),
    ],
    components: [
      for (final component in components)
        (coffeeId: component.coffeeId, country: component.country),
    ],
    methods: [for (final method in methods) (id: method.id, name: method.name)],
    pricePerKg: prices,
    purchases: yearPurchases(lots, prices),
  );
}

List<YearPurchase> yearPurchases(
  List<CoffeeLot> lots,
  Map<String, double> prices,
) => [
  for (final lot in lots)
    if (lot.initialGrams != 0)
      (
        coffeeId: lot.coffeeId,
        atMs: purchaseDate(lot).millisecondsSinceEpoch,
        euros: prices[lot.coffeeId] == null || lot.initialGrams == null
            ? null
            : prices[lot.coffeeId]! * lot.initialGrams! / 1000,
        estimatedDate: DateTime.tryParse(lot.purchaseDate ?? '') == null,
      ),
];

Iterable<int> yearJournalDates(List<Brew> brews, List<CoffeeLot> lots) => [
  for (final brew in brews) brew.brewedAtMs,
  for (final lot in lots)
    if (lot.initialGrams != 0) purchaseDate(lot).millisecondsSinceEpoch,
];
