part of 'app_database.dart';

extension RoasterMigration on AppDatabase {
  /// Links historical coffees using only columns available at schema 35.
  Future<void> backfillRoastersFrom34() async {
    final coffees = await customSelect(
      'SELECT id, roaster FROM coffees ORDER BY id',
    ).get();
    final groups = <String, Map<String, int>>{};
    for (final coffee in coffees) {
      final name = roasterName(coffee.read<String>('roaster'));
      if (name.isEmpty) continue;
      if (name.length > 200) throw ArgumentError('Roaster name too long');
      final spellings = groups.putIfAbsent(roasterKey(name), () => {});
      spellings.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
    final ids = <String, String>{};
    for (final group in groups.entries) {
      final names = group.value.keys.toList()
        ..sort((a, b) {
          final count = group.value[b]!.compareTo(group.value[a]!);
          return count == 0 ? a.compareTo(b) : count;
        });
      final id = const Uuid().v5(
        Namespace.url.value,
        'holybeans:roaster:${group.key}',
      );
      await customStatement(
        'INSERT OR IGNORE INTO roasters (id, name, name_key) VALUES (?, ?, ?)',
        [id, names.first, group.key],
      );
      final row = await customSelect(
        'SELECT id FROM roasters WHERE name_key = ?',
        variables: [Variable.withString(group.key)],
      ).getSingle();
      ids[group.key] = row.read<String>('id');
    }
    for (final coffee in coffees) {
      final coffeeId = coffee.read<String>('id');
      final roasterId = ids[roasterKey(coffee.read<String>('roaster'))];
      if (roasterId == null) {
        await customStatement(
          'DELETE FROM coffee_roaster_links WHERE coffee_id = ?',
          [coffeeId],
        );
      } else {
        await customStatement(
          'INSERT INTO coffee_roaster_links (coffee_id, roaster_id) VALUES (?, ?) '
          'ON CONFLICT(coffee_id) DO UPDATE SET roaster_id = excluded.roaster_id',
          [coffeeId, roasterId],
        );
      }
    }
  }
}
