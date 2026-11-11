import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';

/// Shared row lookups and streams without journal write operations.
class JournalRecordQueries {
  JournalRecordQueries(this.database);
  final AppDatabase database;

  Stream<List<Coffee>> watchCoffees({bool includeArchived = false}) {
    final query = database.select(database.coffees);
    if (!includeArchived) {
      query.where((coffee) => coffee.archivedAtMs.isNull());
    }
    query.orderBy([(coffee) => OrderingTerm.asc(coffee.name)]);
    return query.watch();
  }

  /// Everything the journal holds, archived records included, read once
  /// (for exports).
  Future<List<Coffee>> allCoffees() => database.select(database.coffees).get();

  Future<List<Brew>> allBrews() => database.select(database.brews).get();

  Future<List<BrewMethod>> allMethods() => (database.select(
    database.brewMethods,
  )..orderBy([(method) => OrderingTerm.asc(method.name)])).get();

  Future<List<CoffeeLot>> allLots() =>
      database.select(database.coffeeLots).get();

  /// Every inventory record, archived ones included.
  Stream<List<CoffeeLot>> watchLots() =>
      database.select(database.coffeeLots).watch();

  /// Every coffee's origins, in their order.
  Stream<List<CoffeeComponent>> watchComponents() => (database.select(
    database.coffeeComponents,
  )..orderBy([(row) => OrderingTerm.asc(row.position)])).watch();

  Stream<List<BrewMethod>> watchMethods({bool includeArchived = false}) {
    final query = database.select(database.brewMethods);
    if (!includeArchived) {
      query.where((method) => method.archivedAtMs.isNull());
    }
    query.orderBy([(method) => OrderingTerm.asc(method.name)]);
    return query.watch();
  }

  Stream<List<Grinder>> watchGrinders({bool includeArchived = false}) {
    final query = database.select(database.grinders);
    if (!includeArchived) {
      query.where((grinder) => grinder.archivedAtMs.isNull());
    }
    query.orderBy([(grinder) => OrderingTerm.asc(grinder.name)]);
    return query.watch();
  }

  Stream<List<WaterProfile>> watchWaterProfiles({
    bool includeArchived = false,
  }) {
    final query = database.select(database.waterProfiles);
    if (!includeArchived) {
      query.where((profile) => profile.archivedAtMs.isNull());
    }
    query.orderBy([(profile) => OrderingTerm.asc(profile.name)]);
    return query.watch();
  }

  Future<Coffee?> coffee(String id) => (database.select(
    database.coffees,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<List<CoffeeLot>> coffeeLots(String coffeeId) =>
      (database.select(database.coffeeLots)
            ..where(
              (lot) =>
                  lot.coffeeId.equals(coffeeId) & lot.archivedAtMs.isNull(),
            )
            ..orderBy([(lot) => OrderingTerm.desc(lot.createdAtMs)]))
          .get();

  Future<CoffeeLot?> coffeeLot(String lotId) => (database.select(
    database.coffeeLots,
  )..where((lot) => lot.id.equals(lotId))).getSingleOrNull();

  Future<List<CoffeeComponent>> coffeeComponents(String coffeeId) =>
      (database.select(database.coffeeComponents)
            ..where((row) => row.coffeeId.equals(coffeeId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .get();

  Future<Brew?> brew(String id) => (database.select(
    database.brews,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  /// Every brew of a coffee, archived ones included.
  Future<List<Brew>> brewsOfCoffee(String coffeeId) => (database.select(
    database.brews,
  )..where((row) => row.coffeeId.equals(coffeeId))).get();
}
