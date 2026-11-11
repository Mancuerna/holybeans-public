import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stock_inputs.dart';
import 'package:holybeans/domain/stock.dart' as rules;

/// Row-facing stock results retain the journal records needed by commands.
class LowStock {
  const LowStock._(this.coffee, this._facts);
  final Coffee coffee;
  final rules.LowStock _facts;
  double get freshGrams => _facts.freshGrams;
  double get frozenGrams => _facts.frozenGrams;
  double get dose => _facts.dose;
  int get doses => _facts.doses;
}

class StockArchiveSuggestion {
  const StockArchiveSuggestion(
    this.coffee,
    this.remainingGrams,
    this.meanDose,
    this.methodName,
  );
  final Coffee coffee;
  final double remainingGrams;
  final double meanDose;
  final String methodName;
}

double typicalDose(String coffeeId, List<Brew> brews, {double fallback = 15}) =>
    rules.typicalDose(
      coffeeId,
      brews.map(stockBrewFacts).toList(),
      fallback: fallback,
    );
List<LowStock> lowStock({
  required List<Coffee> coffees,
  required List<Brew> brews,
  required Map<String, double> freshGrams,
  required Map<String, double> frozenGrams,
  Map<String, double>? typicalDoses,
}) {
  final rows = {for (final coffee in coffees) coffee.id: coffee};
  return [
    for (final value in rules.lowStock(
      coffees: coffees.map(stockCoffeeFacts).toList(),
      brews: brews.map(stockBrewFacts).toList(),
      freshGrams: freshGrams,
      frozenGrams: frozenGrams,
      typicalDoses: typicalDoses,
    ))
      LowStock._(rows[value.coffee.id]!, value),
  ];
}

int? frozenAtRoastAge(FrozenPortion portion, DateTime? roastDate) =>
    rules.frozenAtRoastAge(stockPortionFacts(portion), roastDate);
double? unfrozenGrams(CoffeeLot lot) => rules.unfrozenGrams(stockLotFacts(lot));
Map<String, double> frozenGramsByCoffee(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
) => rules.frozenGramsByCoffee(
  lots.map(stockLotFacts).toList(),
  portions.map(stockPortionFacts).toList(),
);
Map<String, DateTime> oldestFrozenDatesByCoffee(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
) => rules.oldestFrozenDatesByCoffee(
  lots.map(stockLotFacts).toList(),
  portions.map(stockPortionFacts).toList(),
);
Map<String, double> unfrozenGramsByCoffee(List<CoffeeLot> lots) =>
    rules.unfrozenGramsByCoffee(lots.map(stockLotFacts).toList());
int? oldestFreezeDays(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
  DateTime now,
) => rules.oldestFreezeDays(
  lots.map(stockLotFacts).toList(),
  portions.map(stockPortionFacts).toList(),
  now,
);
double? meanMethodDose(Brew brew, List<Brew> history) => rules.meanMethodDose(
  stockBrewFacts(brew),
  history.map(stockBrewFacts).toList(),
);
StockArchiveSuggestion? stockArchiveSuggestion({
  required Coffee coffee,
  required Brew brew,
  required List<Brew> history,
  required List<CoffeeLot> lots,
  required List<FrozenPortion> portions,
}) {
  final value = rules.stockArchiveSuggestion(
    coffee: stockCoffeeFacts(coffee),
    brew: stockBrewFacts(brew),
    history: history.map(stockBrewFacts).toList(),
    lots: lots.map(stockLotFacts).toList(),
    portions: portions.map(stockPortionFacts).toList(),
  );
  return value == null
      ? null
      : StockArchiveSuggestion(
          coffee,
          value.remainingGrams,
          value.meanDose,
          value.methodName,
        );
}

/// A stock snapshot with original rows available for editing and navigation.
class CoffeeStock {
  CoffeeStock({
    required this.lots,
    required List<FrozenPortion> portions,
    this.adjustments = const [],
  }) : _rows = {for (final row in portions) row.id: row},
       _facts = rules.CoffeeStock(
         lots: lots.map(stockLotFacts).toList(),
         portions: portions.map(stockPortionFacts).toList(),
         adjustments: adjustments.map(stockAdjustmentFacts).toList(),
       );
  final List<CoffeeLot> lots;
  final List<StockAdjustment> adjustments;
  final Map<String, FrozenPortion> _rows;
  final rules.CoffeeStock _facts;
  late final List<FrozenPortion> frozen = [
    for (final row in _facts.frozen) _rows[row.id]!,
  ];
  late final List<FrozenPortion> thawed = [
    for (final row in _facts.thawed) _rows[row.id]!,
  ];
  double? get initialGrams => _facts.initialGrams;
  double? get signedRemainingGrams => _facts.signedRemainingGrams;
  double? get remainingGrams => _facts.remainingGrams;
  double get frozenGrams => _facts.frozenGrams;
  bool get onlyFrozen => _facts.onlyFrozen;
  List<FrozenPortion> get frozenOldestFirst => [
    for (final row in _facts.frozenOldestFirst) _rows[row.id]!,
  ];
  double? get consumedGrams => _facts.consumedGrams;
  DateTime? roastDateOf(FrozenPortion portion) =>
      _facts.roastDateOf(stockPortionFacts(portion));
  int? get frozenOnlyAge => _facts.frozenOnlyAge;
}
