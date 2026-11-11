import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';

CoffeeSuggestions coffeeSuggestionsFromRows(
  List<Coffee> coffees,
  List<CoffeeComponent> origins, {
  Iterable<String> roasterNames = const [],
}) => CoffeeSuggestions(
  [for (final row in coffees) (name: row.name, roaster: row.roaster)],
  [
    for (final row in origins)
      (
        region: row.region,
        variety: row.variety,
        process: row.process,
        farm: row.farm,
        producer: row.producer,
        harvest: row.harvest,
      ),
  ],
  roasterNames: roasterNames,
);
