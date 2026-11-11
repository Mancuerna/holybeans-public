import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/text_suggestions.dart';

/// Date-independent list inputs, reused until the journal or freezer changes.
class BeanListData {
  BeanListData(this.data, this.portions);

  final JournalData data;
  final List<FrozenPortion> portions;

  late final lastBrewAt = data.lastBrewAt;
  late final latestRoastDates = _latestRoastDates(data.lots);
  late final oldestFrozenDates = oldestFrozenDatesByCoffee(data.lots, portions);
  late final frozenGrams = frozenGramsByCoffee(data.lots, portions);
  late final freshGrams = unfrozenGramsByCoffee(data.lots);
  late final tabs = [
    data.coffees.where(_available).toList(),
    data.coffees.where(_frozen).toList(),
    data.coffees.where((coffee) => coffee.archivedAtMs != null).toList(),
  ];

  // Build the search index only when a query first needs it.
  late final searchText = _searchText(data);

  bool _frozen(Coffee coffee) =>
      coffee.archivedAtMs == null && (frozenGrams[coffee.id] ?? 0) > 0;

  // A coffee whose only remaining stock is frozen lives in the Frozen tab.
  bool _available(Coffee coffee) =>
      coffee.archivedAtMs == null &&
      !(_frozen(coffee) && freshGrams[coffee.id] == 0);
}

Map<String, DateTime> _latestRoastDates(List<CoffeeLot> lots) {
  final result = <String, DateTime>{};
  for (final lot in lots) {
    final roastDate = lot.roastDate == null
        ? null
        : DateTime.tryParse(lot.roastDate!);
    if (roastDate == null) continue;
    final previous = result[lot.coffeeId];
    if (previous == null || roastDate.isAfter(previous)) {
      result[lot.coffeeId] = roastDate;
    }
  }
  return result;
}

Map<String, String> _searchText(JournalData data) {
  final origins = <String, List<String>>{};
  for (final component in data.components) {
    (origins[component.coffeeId] ??= []).add(
      [
        component.country,
        component.region,
        component.variety,
        component.process,
      ].whereType<String>().join(' '),
    );
  }
  return {
    for (final coffee in data.coffees)
      coffee.id: foldSuggestion(
        '${coffee.name} ${coffee.roaster} '
        '${origins[coffee.id]?.join(' ') ?? ''} ${coffee.flavorProfile ?? ''}',
      ),
  };
}
