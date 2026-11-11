import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stats_inputs.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_insights.dart' as rules;

export 'package:holybeans/domain/stats_insights.dart'
    hide
        coffeeValues,
        learningCurve,
        medianDaysToFirstBrew,
        pricePerKgByRoaster,
        purchaseDate,
        purchases,
        ratingByTemperature,
        styleAverages;

Map<int, rules.RatedGroup> ratingByTemperature(
  Iterable<Brew> brews, {
  int step = 2,
}) => rules.ratingByTemperature(brews.map(statsBrew), step: step);
Map<int, rules.RatedGroup> learningCurve(
  Iterable<Brew> allBrews,
  Iterable<Brew> inRange, {
  int cap = 8,
}) => rules.learningCurve(
  allBrews.map(statsBrew),
  inRange.map(statsBrew),
  cap: cap,
);
List<rules.CoffeeValue> coffeeValues(
  Iterable<Brew> brews,
  Iterable<Coffee> coffees,
  Map<String, double> prices,
) => rules.coffeeValues(brews.map(statsBrew), coffees.map(statsCoffee), prices);
DateTime purchaseDate(CoffeeLot lot) => rules.purchaseDate(statsLot(lot));
List<rules.Purchase> purchases(
  Iterable<CoffeeLot> lots,
  Map<String, double> prices, {
  DateTime? from,
}) => rules.purchases(lots.map(statsLot), prices, from: from);
List<rules.RoasterPrice> pricePerKgByRoaster(
  Iterable<Coffee> coffees,
  Iterable<CoffeeLot> lots,
  Map<String, double> prices, {
  DateTime? from,
}) => rules.pricePerKgByRoaster(
  coffees.map(statsCoffee),
  lots.map(statsLot),
  prices,
  from: from,
);
double? medianDaysToFirstBrew(
  Iterable<Brew> allBrews,
  Iterable<Brew> inRange,
  Iterable<CoffeeLot> lots,
) => rules.medianDaysToFirstBrew(
  allBrews.map(statsBrew),
  inRange.map(statsBrew),
  lots.map(statsLot),
);
Map<BrewStyle, rules.StyleAverages> styleAverages(
  Iterable<Brew> brews,
  BrewStyle Function(Brew) styleOf,
) => rules.styleAverages(
  brews.map((brew) => statsBrew(brew, style: styleOf(brew))),
);
