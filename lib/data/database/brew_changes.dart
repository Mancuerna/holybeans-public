import 'package:drift/drift.dart';

/// Connection-local revisions for live lists. Triggers include imports,
/// restores, cascades and writes that keep the same updated_at_ms value.
/// Nothing is added to the persisted journal or its backup schema.
Future<void> installBrewChanges(GeneratedDatabase database) async {
  await database.customStatement('''
    CREATE TEMP TABLE brew_changes (
      revision INTEGER PRIMARY KEY AUTOINCREMENT,
      brew_id TEXT NOT NULL UNIQUE
    )
  ''');
  for (final (event, id) in [('INSERT', 'NEW.id'), ('DELETE', 'OLD.id')]) {
    await database.customStatement('''
      CREATE TEMP TRIGGER brew_changes_${event.toLowerCase()}
      AFTER $event ON main.brews BEGIN
        DELETE FROM brew_changes WHERE brew_id = $id;
        INSERT INTO brew_changes (brew_id) VALUES ($id);
      END
    ''');
  }
  await database.customStatement('''
    CREATE TEMP TRIGGER brew_changes_update AFTER UPDATE ON main.brews BEGIN
      DELETE FROM brew_changes WHERE brew_id IN (OLD.id, NEW.id);
      INSERT INTO brew_changes (brew_id) VALUES (OLD.id);
      INSERT INTO brew_changes (brew_id)
        SELECT NEW.id WHERE NEW.id != OLD.id;
    END
  ''');
}
