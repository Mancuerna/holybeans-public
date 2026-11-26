part of 'app_database.dart';

/// Read-only projection with the same columns as brews. Keep recorded names
/// as a fallback for journal entries without a catalog link.
class _BrewDisplayRows extends $BrewsTable {
  _BrewDisplayRows(super.attachedDatabase);

  @override
  String get actualTableName => 'display_brews';
}

Future<void> _installBrewDisplayRows(AppDatabase db) async {
  const catalogs = {
    'method': 'brew_methods',
    'grinder': 'grinders',
    'water_profile': 'water_profiles',
    'recipient': 'recipients',
  };
  final names = {
    for (final entry in catalogs.entries)
      '${entry.key}_name':
          'coalesce((SELECT name FROM ${entry.value} WHERE id = b.${entry.key}_id), b.${entry.key}_name)',
  };
  final columns = db.brews.$columns.map((column) {
    final name = column.$name;
    return '${names[name] ?? 'b."$name"'} AS "$name"';
  });
  await db.customStatement(
    'CREATE TEMP VIEW display_brews AS SELECT ${columns.join(', ')} FROM main.brews b',
  );

  // A rename affects the same history pages and cached per-coffee summaries
  // as an edit of each linked brew, without rewriting historical measurements.
  for (final entry in catalogs.entries) {
    await db.customStatement('''
      CREATE TEMP TRIGGER ${entry.key}_brew_rename
      AFTER UPDATE OF name ON main.${entry.value} WHEN OLD.name != NEW.name BEGIN
        INSERT OR REPLACE INTO brew_changes (brew_id)
          SELECT id FROM brews WHERE ${entry.key}_id = NEW.id;
        INSERT OR REPLACE INTO brew_coffee_changes (coffee_id, revision)
          SELECT DISTINCT coffee_id, (SELECT max(revision) FROM brew_changes)
          FROM brews WHERE ${entry.key}_id = NEW.id;
      END
    ''');
  }
}
