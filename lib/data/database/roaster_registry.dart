part of 'app_database.dart';

// Additive links preserve the exact roaster text on every existing coffee.
class RoasterRegistry {
  RoasterRegistry(this.database);
  final AppDatabase database;

  Future<String?> resolve(String? name) async {
    final clean = roasterName(name ?? '');
    if (clean.isEmpty) return null;
    if (clean.length > 200) throw ArgumentError('Roaster name too long');
    final key = roasterKey(clean);
    final found = await (database.select(
      database.roasters,
    )..where((r) => r.nameKey.equals(key))).getSingleOrNull();
    if (found != null) return found.id;
    final id = const Uuid().v5(Namespace.url.value, 'holybeans:roaster:$key');
    await database
        .into(database.roasters)
        .insert(
          Roaster(id: id, name: clean, nameKey: key),
          mode: InsertMode.insertOrIgnore,
        );
    return (await (database.select(
      database.roasters,
    )..where((r) => r.nameKey.equals(key))).getSingle()).id;
  }

  Future<void> linkCoffee(String id, String name) async {
    final roasterId = await resolve(name);
    if (roasterId == null) {
      await (database.delete(
        database.coffeeRoasterLinks,
      )..where((r) => r.coffeeId.equals(id))).go();
    } else {
      await database
          .into(database.coffeeRoasterLinks)
          .insertOnConflictUpdate(
            CoffeeRoasterLink(coffeeId: id, roasterId: roasterId),
          );
    }
  }

  Future<void> backfill() async {
    final coffees = await (database.select(
      database.coffees,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    // Match existing directory spelling: most common, with lexical tie break.
    final groups = <String, Map<String, int>>{};
    for (final coffee in coffees) {
      final name = roasterName(coffee.roaster);
      if (name.isEmpty) continue;
      final spellings = groups.putIfAbsent(roasterKey(name), () => {});
      spellings.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final spellings in groups.values) {
      final names = spellings.keys.toList()
        ..sort((a, b) {
          final order = spellings[b]!.compareTo(spellings[a]!);
          return order == 0 ? a.compareTo(b) : order;
        });
      await resolve(names.first);
    }
    for (final coffee in coffees) {
      await linkCoffee(coffee.id, coffee.roaster);
    }
  }
}
