import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stats_inputs.dart';
import 'package:holybeans/domain/brew_stats.dart' as rules;
import 'package:holybeans/domain/freshness.dart';

export 'package:holybeans/domain/brew_stats.dart'
    hide brewCost, brewsPerDay, pricePerKgByCoffee;

Map<String, double> pricePerKgByCoffee(
  List<Coffee> coffees,
  List<CoffeeLot> lots,
) => rules.pricePerKgByCoffee(
  coffees.map(statsCoffee).toList(),
  lots.map(statsLot).toList(),
);

double? brewCost(Brew brew, Map<String, double> pricePerKg) =>
    rules.brewCost(brew.coffeeId, brew.doseGrams, pricePerKg);

Map<DateTime, int> brewsPerDay(Iterable<Brew> brews) =>
    rules.brewsPerDay(brews.map((brew) => brew.brewedAtMs));

rules.BrewStats brewStatsFromRows({
  required List<Brew> brews,
  required List<Coffee> coffees,
  required List<CoffeeComponent> components,
  required BrewStyle Function(Brew brew) styleOf,
  required rules.StatsRange range,
  required DateTime now,
  required String languageCode,
  Map<String, double> pricePerKg = const {},
}) => rules.BrewStats.compute(
  brews: [for (final brew in brews) statsBrew(brew, style: styleOf(brew))],
  coffees: coffees.map(statsCoffee).toList(),
  components: components.map(statsComponent).toList(),
  range: range,
  now: now,
  languageCode: languageCode,
  pricePerKg: pricePerKg,
);
