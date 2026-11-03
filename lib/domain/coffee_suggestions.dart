import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/text_suggestions.dart';

/// Suggestions from the user's own coffees, including archived ones.
class CoffeeSuggestions {
  CoffeeSuggestions(
    List<Coffee> coffees,
    List<CoffeeComponent> origins, {
    Iterable<String> roasterNames = const [],
  }) : names = uniqueSuggestions(coffees.map((coffee) => coffee.name)),
       roasters = uniqueSuggestions([
         ...coffees.map((coffee) => coffee.roaster),
         ...roasterNames,
       ]),
       regions = uniqueSuggestions(origins.map((origin) => origin.region)),
       varieties = uniqueSuggestions(origins.map((origin) => origin.variety)),
       processes = uniqueSuggestions(origins.map((origin) => origin.process)),
       farms = uniqueSuggestions(origins.map((origin) => origin.farm)),
       producers = uniqueSuggestions(origins.map((origin) => origin.producer)),
       harvests = uniqueSuggestions(origins.map((origin) => origin.harvest));

  final List<String> names;
  final List<String> roasters;
  final List<String> regions;
  final List<String> varieties;
  final List<String> processes;
  final List<String> farms;
  final List<String> producers;
  final List<String> harvests;
}
