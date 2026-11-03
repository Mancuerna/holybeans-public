import 'package:holybeans/data/database/app_database.dart';

/// The journal's live data, as the shell receives it from the database.
class JournalData {
  JournalData({
    required List<Coffee> coffees,
    required List<Brew> brews,
    required List<CoffeeLot> lots,
    required List<CoffeeComponent> components,
    Map<String, String> covers = const {},
    List<StockAdjustment> adjustments = const [],
  }) : coffees = List.unmodifiable(coffees),
       brews = List.unmodifiable(brews),
       lots = List.unmodifiable(lots),
       components = List.unmodifiable(components),
       covers = Map.unmodifiable(covers),
       adjustments = List.unmodifiable(adjustments);

  /// All coffees and brews, archived ones included.
  final List<Coffee> coffees;
  final List<Brew> brews;
  final List<CoffeeLot> lots;
  final List<StockAdjustment> adjustments;
  final List<CoffeeComponent> components;

  /// Cover photo file of each coffee that has photos, by coffee ID.
  final Map<String, String> covers;

  String? coverOf(String coffeeId) => covers[coffeeId];

  List<CoffeeLot> activeLotsOf(String coffeeId) => [
    for (final lot in lots)
      if (lot.coffeeId == coffeeId && lot.archivedAtMs == null) lot,
  ];

  List<CoffeeComponent> componentsOf(String coffeeId) => [
    for (final component in components)
      if (component.coffeeId == coffeeId) component,
  ];
}
