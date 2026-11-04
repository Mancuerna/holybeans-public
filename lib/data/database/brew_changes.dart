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
  await database.customStatement('''
    CREATE TEMP TABLE brew_coffee_changes (
      coffee_id TEXT PRIMARY KEY NOT NULL,
      revision INTEGER NOT NULL
    ) WITHOUT ROWID
  ''');
  // REPLACE need not run DELETE triggers when recursive_triggers is off.
  // Capture the displaced row's owner before SQLite replaces it.
  await database.customStatement('''
    CREATE TEMP TRIGGER brew_coffee_before_insert BEFORE INSERT ON main.brews BEGIN
      INSERT OR REPLACE INTO brew_coffee_changes
        SELECT coffee_id, (SELECT coalesce(max(revision), 0) + 1 FROM brew_changes)
        FROM main.brews WHERE id = NEW.id;
    END
  ''');
  for (final (event, id) in [('INSERT', 'NEW.id'), ('DELETE', 'OLD.id')]) {
    await database.customStatement('''
      CREATE TEMP TRIGGER brew_changes_${event.toLowerCase()}
      AFTER $event ON main.brews BEGIN
        DELETE FROM brew_changes WHERE brew_id = $id;
        INSERT INTO brew_changes (brew_id) VALUES ($id);
        INSERT OR REPLACE INTO brew_coffee_changes VALUES (
          ${event == 'INSERT' ? 'NEW' : 'OLD'}.coffee_id,
          (SELECT max(revision) FROM brew_changes)
        );
      END
    ''');
  }
  await database.customStatement('''
    CREATE TEMP TRIGGER brew_changes_update AFTER UPDATE ON main.brews BEGIN
      DELETE FROM brew_changes WHERE brew_id IN (OLD.id, NEW.id);
      INSERT INTO brew_changes (brew_id) VALUES (OLD.id);
      INSERT INTO brew_changes (brew_id)
        SELECT NEW.id WHERE NEW.id != OLD.id;
      INSERT OR REPLACE INTO brew_coffee_changes VALUES (OLD.coffee_id, (SELECT max(revision) FROM brew_changes));
      INSERT OR REPLACE INTO brew_coffee_changes VALUES (NEW.coffee_id, (SELECT max(revision) FROM brew_changes));
    END
  ''');
}
