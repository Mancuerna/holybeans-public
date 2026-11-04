import 'package:drift/drift.dart';

/// Additive access paths, also installed when opening an existing journal.
/// They do not change row/backup formats or require rewriting journal data.
Future<void> installJournalIndexes(GeneratedDatabase database) async {
  for (final entry in {
    'brew_history': 'brewed_at_ms DESC, created_at_ms DESC, id ASC',
    'brew_active_history':
        'archived_at_ms, brewed_at_ms DESC, created_at_ms DESC, id ASC',
    'brew_coffee_history':
        'coffee_id, brewed_at_ms DESC, created_at_ms DESC, id ASC',
    'brew_coffee_recipe': 'coffee_id, archived_at_ms, is_favorite DESC, brewed_at_ms DESC, created_at_ms DESC, id ASC',
  }.entries) {
    await database.customStatement(
      'CREATE INDEX IF NOT EXISTS ${entry.key} ON brews (${entry.value})',
    );
  }
}
