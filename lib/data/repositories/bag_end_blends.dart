import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:uuid/uuid.dart';

class BagEndBlends {
  BagEndBlends(this.db, this.records, this.coffees);
  final AppDatabase db;
  final JournalRecordQueries records;
  final CoffeeRepository coffees;

  Future<bool> _empty(String id) async {
    final lots = await records.coffeeLots(id);
    if (lots.isEmpty || lots.any((l) => l.remainingGrams != 0)) return false;
    final frozen =
        await (db.select(db.frozenPortions)
              ..where(
                (p) =>
                    p.lotId.isIn(lots.map((l) => l.id)) &
                    p.remainingGrams.isBiggerThanValue(0),
              )
              ..limit(1))
            .getSingleOrNull();
    return frozen == null;
  }

  Future<({String id, List<Coffee> empty})> create(
    String name,
    Map<String, double> amounts,
  ) => db.transaction(() async {
    final sources = <String, Coffee>{};
    final lots = <CoffeeLot>[];
    for (final entry in amounts.entries) {
      final lot = await records.coffeeLot(entry.key);
      final available = lot?.remainingGrams;
      if (lot == null ||
          available == null ||
          lot.archivedAtMs != null ||
          !entry.value.isFinite ||
          entry.value <= 0 ||
          entry.value > available ||
          (roundStockGrams(entry.value) - entry.value).abs() > stockTolerance) {
        throw StateError('Invalid blend allocation');
      }
      final coffee = await records.coffee(lot.coffeeId);
      if (coffee == null ||
          coffee.archivedAtMs != null ||
          coffee.mixedAtMs != null) {
        throw StateError('Ineligible blend source');
      }
      lots.add(lot);
      sources[coffee.id] = coffee;
    }
    if (sources.length < 2) throw ArgumentError('Select at least two coffees');
    final dates = lots.map((l) => l.roastDate).toSet();
    final id = await coffees.createCoffee(
      name: name,
      roaster: '',
      initialGrams: roundStockGrams(amounts.values.reduce((a, b) => a + b)),
      roastDate: dates.length == 1 ? dates.single : null,
    );
    final destination = (await records.coffeeLots(id)).single;
    final now = DateTime.now().millisecondsSinceEpoch;
    await (db.update(db.coffees)..where((c) => c.id.equals(id))).write(
      CoffeesCompanion(
        mixedAtMs: Value(now),
        isDecaf: Value(sources.values.every((c) => c.isDecaf)),
      ),
    );
    for (final lot in lots) {
      final after = roundStockGrams(lot.remainingGrams! - amounts[lot.id]!);
      await (db.update(db.coffeeLots)..where((l) => l.id.equals(lot.id))).write(
        CoffeeLotsCompanion(
          remainingGrams: Value(after),
          updatedAtMs: Value(now),
        ),
      );
      final rowId = const Uuid().v4();
      await db
          .into(db.stockAdjustments)
          .insert(
            StockAdjustment(
              id: rowId,
              operationId: rowId,
              reason: 'blend',
              coffeeId: lot.coffeeId,
              lotId: lot.id,
              previousGrams: lot.remainingGrams,
              resultingGrams: after,
              blendLotId: destination.id,
              sourceRoastDate: lot.roastDate,
              notes: name.trim(),
              createdAtMs: now,
            ),
          );
    }
    return (
      id: id,
      empty: [
        for (final coffee in sources.values)
          if (await _empty(coffee.id)) coffee,
      ],
    );
  });

  Future<void> archiveEmpty(Map<String, double?> ratings) =>
      db.transaction(() async {
        for (final entry in ratings.entries) {
          final coffee = await records.coffee(entry.key);
          if (coffee != null &&
              coffee.archivedAtMs == null &&
              await _empty(entry.key)) {
            await coffees.setCoffeeArchived(
              entry.key,
              archived: true,
              rating: entry.value,
            );
          }
        }
      });

  Future<List<StockAdjustment>> contributions(String coffeeId) {
    final lots = db.selectOnly(db.coffeeLots)
      ..addColumns([db.coffeeLots.id])
      ..where(db.coffeeLots.coffeeId.equals(coffeeId));
    return (db.select(
      db.stockAdjustments,
    )..where((r) => r.blendLotId.isInQuery(lots))).get();
  }
}
