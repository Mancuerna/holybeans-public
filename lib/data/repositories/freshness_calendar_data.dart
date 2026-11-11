import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/freshness_calendar.dart';

List<CalendarLot> calendarLots(JournalData data, List<FrozenPortion> portions) {
  final coffees = {
    for (final coffee in data.coffees)
      if (coffee.archivedAtMs == null) coffee.id: coffee,
  };
  final result = <CalendarLot>[];
  final withLots = <String>{};
  final frozenByLot = <String, double>{};
  for (final portion in portions) {
    if (portion.remainingGrams > 0) {
      frozenByLot.update(
        portion.lotId,
        (grams) => grams + portion.remainingGrams,
        ifAbsent: () => portion.remainingGrams,
      );
    }
  }
  for (final lot in data.lots) {
    final coffee = coffees[lot.coffeeId];
    if (coffee == null || lot.archivedAtMs != null) continue;
    withLots.add(coffee.id);
    final grams = unfrozenGrams(lot);
    CalendarLot entry(double? grams, {bool frozen = false}) => CalendarLot(
      id: frozen ? 'frozen:${lot.id}' : lot.id,
      coffeeId: coffee.id,
      coffeeName: coffee.name,
      roaster: coffee.roaster,
      grams: grams,
      roastDate: DateTime.tryParse(lot.roastDate ?? ''),
      openedDate: DateTime.tryParse(lot.openedDate ?? ''),
      roastLevel: coffee.roastLevel,
      restDays: coffee.restDays,
      frozenPauseDays: lot.frozenPauseDays ?? 0,
      frozen: frozen,
    );
    if (grams == null || grams > 0) result.add(entry(grams));
    final frozen = frozenByLot[lot.id] ?? 0;
    if (frozen > 0) result.add(entry(frozen, frozen: true));
  }
  for (final coffee in coffees.values) {
    if (withLots.contains(coffee.id)) continue;
    result.add(
      CalendarLot(
        id: coffee.id,
        coffeeId: coffee.id,
        coffeeName: coffee.name,
        roaster: coffee.roaster,
        grams: null,
      ),
    );
  }
  return result..sort((a, b) {
    final name = a.coffeeName.toLowerCase().compareTo(
      b.coffeeName.toLowerCase(),
    );
    if (name != 0) return name;
    final date = (a.roastDate ?? DateTime(9999)).compareTo(
      b.roastDate ?? DateTime(9999),
    );
    return date != 0 ? date : a.id.compareTo(b.id);
  });
}
