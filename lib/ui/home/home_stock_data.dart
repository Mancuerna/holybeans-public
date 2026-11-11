import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/domain/stock.dart';

/// Home's stock and recipe inputs, independent of the current date or locale.
typedef HomeStockData = ({
  List<Coffee> active,
  List<Brew> activeBrews,
  List<Coffee> atHand,
  Map<String, int> lastBrewAt,
  Map<String, double> freshByCoffee,
  double freshTotal,
  double frozenTotal,
  List<LowStock> low,
  Set<String> lowIds,
  Map<String, List<Brew>> brewsByCoffee,
});

/// Derives stock totals and groups recipes for one journal/freezer snapshot.
HomeStockData homeStockData(JournalData data, List<FrozenPortion> portions) {
  final active = data.coffees
      .where((coffee) => coffee.archivedAtMs == null)
      .toList();
  final activeIds = {for (final coffee in active) coffee.id};
  final activeBrews = (data.overview?.seeds.values.toList() ?? data.brews)
      .where((brew) => brew.archivedAtMs == null)
      .toList();
  final frozenByCoffee = frozenGramsByCoffee(data.lots, portions);
  final freshByCoffee = unfrozenGramsByCoffee(data.lots);
  double sumActive(Map<String, double> grams) => grams.entries
      .where((entry) => activeIds.contains(entry.key))
      .fold(0, (sum, entry) => sum + entry.value);
  final lastBrewAt = data.lastBrewAt;
  // Unfrozen or unknown stock, ordered by last brew and then creation.
  final atHand =
      active
          .where(
            (coffee) =>
                !((frozenByCoffee[coffee.id] ?? 0) > 0 &&
                    freshByCoffee[coffee.id] == 0),
          )
          .toList()
        ..sort((first, second) {
          final firstBrew = lastBrewAt[first.id];
          final secondBrew = lastBrewAt[second.id];
          if (firstBrew != null || secondBrew != null) {
            if (firstBrew == null) return 1;
            if (secondBrew == null) return -1;
            return secondBrew.compareTo(firstBrew);
          }
          return second.createdAtMs.compareTo(first.createdAtMs);
        });
  final low = lowStock(
    coffees: data.coffees,
    brews: data.brews,
    freshGrams: freshByCoffee,
    frozenGrams: frozenByCoffee,
    typicalDoses: data.overview?.doses,
  );
  final brewsByCoffee = <String, List<Brew>>{};
  for (final brew in activeBrews) {
    brewsByCoffee.putIfAbsent(brew.coffeeId, () => []).add(brew);
  }
  return (
    active: active,
    activeBrews: activeBrews,
    atHand: atHand,
    lastBrewAt: lastBrewAt,
    freshByCoffee: freshByCoffee,
    freshTotal: sumActive(freshByCoffee),
    frozenTotal: sumActive(frozenByCoffee),
    low: low,
    lowIds: {for (final item in low) item.coffee.id},
    brewsByCoffee: brewsByCoffee,
  );
}
