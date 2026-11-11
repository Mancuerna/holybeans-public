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
  for (final (name, table, columns) in const [
    ('brew_lot_lookup', 'brews', 'lot_id'),
    ('brew_method_lookup', 'brews', 'method_id'),
    ('brew_water_lookup', 'brews', 'water_profile_id'),
    ('brew_frozen_portion_lookup', 'brews', 'frozen_portion_id'),
    ('import_record_entity_lookup', 'import_records', 'local_entity, local_id'),
    ('coffee_lot_coffee_lookup', 'coffee_lots', 'coffee_id'),
    ('frozen_portion_lot_lookup', 'frozen_portions', 'lot_id'),
    ('tool_method_lookup', 'tool_method_links', 'method_id, tool_id'),
  ]) {
    await database.customStatement(
      'CREATE INDEX IF NOT EXISTS $name ON $table ($columns)',
    );
  }
}
