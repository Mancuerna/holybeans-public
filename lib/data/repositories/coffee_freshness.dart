import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stock.dart';

BrewStyle brewStyleOf(Brew brew, List<BrewMethod> methods) {
  final method = methods.where((row) => row.id == brew.methodId).firstOrNull;
  return isEspressoMethod(
        category: method?.category,
        methodName: method?.name ?? brew.methodName,
      )
      ? BrewStyle.espresso
      : BrewStyle.filter;
}

/// The style last brewed with the coffee with [coffeeId], archived brews
/// included; filter when it has never been brewed.
BrewStyle lastBrewStyle(
  String coffeeId,
  List<Brew> brews,
  List<BrewMethod> methods,
) {
  Brew? last;
  for (final brew in brews) {
    if (brew.coffeeId == coffeeId &&
        (last == null || brew.brewedAtMs > last.brewedAtMs)) {
      last = brew;
    }
  }
  return last == null ? BrewStyle.filter : brewStyleOf(last, methods);
}

/// The phase [coffee] is in today for [style] or, without one, for the
/// style last brewed with it. Null without a roast date, once archived, or
/// while all that is left is frozen, since freezing stops the clock. The
/// one rule Home and the bean cards follow; `JournalViewModel.freshnessOf`
/// keeps it between changes.
FreshnessToday? freshnessToday(
  Coffee coffee, {
  required JournalData data,
  required List<BrewMethod> methods,
  required List<FrozenPortion> portions,
  BrewStyle? style,
  DateTime? now,
}) {
  if (coffee.archivedAtMs != null) return null;
  final lots = data.activeLotsOf(coffee.id);
  if (CoffeeStock(lots: lots, portions: portions).frozenOnlyAge != null) {
    return null;
  }
  final freshness = coffeeFreshness(
    coffee: coffee,
    lots: lots,
    coffees: data.coffees,
    brews: const [],
    allLots: data.lots,
    components: data.components,
    methods: methods,
    now: now,
  );
  if (freshness == null) return null;
  final judged = style ?? lastBrewStyle(coffee.id, data.brews, methods);
  return (
    phase: freshness.phase(judged),
    style: judged,
    day: freshness.day,
    window: freshness.windows[judged]!,
  );
}

CoffeeFreshness? coffeeFreshness({
  required Coffee coffee,
  required List<CoffeeLot> lots,
  required List<Coffee> coffees,
  required List<Brew> brews,
  required List<CoffeeLot> allLots,
  required List<CoffeeComponent> components,
  required List<BrewMethod> methods,
  int? frozenOnlyAge,
  DateTime? now,
}) => coffeeFreshnessFacts(
  coffee: _coffee(coffee),
  lots: lots.map(_lot).toList(),
  coffees: coffees.map(_coffee).toList(),
  brews: [
    for (final brew in brews)
      (
        coffeeId: brew.coffeeId,
        lotId: brew.lotId,
        rating: brew.rating,
        brewedAtMs: brew.brewedAtMs,
        style: brewStyleOf(brew, methods),
      ),
  ],
  allLots: allLots.map(_lot).toList(),
  frozenOnlyAge: frozenOnlyAge,
  now: now,
);

FreshnessCoffee _coffee(Coffee row) => (
  id: row.id,
  roaster: row.roaster,
  roastLevel: row.roastLevel,
  restDays: row.restDays,
);
FreshnessLot _lot(CoffeeLot row) => (
  id: row.id,
  roastDate: row.roastDate,
  openedDate: row.openedDate,
  frozenPauseDays: row.frozenPauseDays,
);
