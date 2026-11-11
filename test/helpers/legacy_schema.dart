import 'package:holybeans/data/database/app_database.dart';

/// Reconstructs a published layout in a temporary test database. All tools
/// must have a legacy owner or exactly one association. Never use on the app.
Future<void> reconstructLegacySchema(AppDatabase db, int version) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  await db.transaction(() async {
    // Current access indexes may refer to columns absent from old fixtures.
    for (final name in [
      'brew_history',
      'brew_active_history',
      'brew_coffee_history',
      'brew_coffee_recipe',
      'brew_lot_lookup',
      'brew_method_lookup',
      'brew_water_lookup',
      'brew_frozen_portion_lookup',
      'import_record_entity_lookup',
      'coffee_lot_coffee_lookup',
      'frozen_portion_lot_lookup',
      'tool_method_lookup',
      'coffee_photo_file_lookup',
      'brew_photo_file_lookup',
    ]) {
      await db.customStatement('DROP INDEX IF EXISTS $name');
    }
    if (version < 38) {
      await db.customStatement(
        'ALTER TABLE recipients DROP COLUMN is_portafilter',
      );
      await db.customStatement(
        'ALTER TABLE brews DROP COLUMN recipient_is_portafilter',
      );
    }
    if (version < 37) {
      for (final table in [
        'piston_method_links',
        'piston_measurements',
        'piston_maintenances',
        'piston_machines',
      ]) {
        await db.customStatement('DROP TABLE $table');
      }
    }
    if (version < 36) {
      await db.customStatement(
        'ALTER TABLE grinders DROP COLUMN has_adjustable_feeder_rpm',
      );
      for (final column in ['feeder_rpm', 'brix', 'brix_factor']) {
        await db.customStatement('ALTER TABLE brews DROP COLUMN $column');
      }
    }
    if (version < 35) {
      for (final table in [
        'cafe_drink_photos',
        'cafe_drinks',
        'coffee_roaster_links',
        'cafes',
        'roasters',
      ]) {
        await db.customStatement('DROP TABLE $table');
      }
    }
    if (version < 34) {
      await db.customStatement(
        'ALTER TABLE app_preferences DROP COLUMN scales_json',
      );
    }
    if (version < 31) {
      await db.customStatement('ALTER TABLE brews DROP COLUMN recipient_id');
      await db.customStatement('ALTER TABLE brews DROP COLUMN recipient_name');
      await db.customStatement('ALTER TABLE brews DROP COLUMN recipient_grams');
      await db.customStatement(
        'ALTER TABLE brew_methods DROP COLUMN default_recipient_id',
      );
      await db.customStatement('DROP TABLE recipients');
    }
    if (version < 30) await db.customStatement('DROP TABLE stock_adjustments');
    if (version < 29) {
      await db.customStatement(
        'ALTER TABLE brews DROP COLUMN stock_review_pending',
      );
    }
    if (version < 28) {
      await db.customStatement('DROP TABLE cupping_session_cups');
      await db.customStatement('DROP TABLE cupping_sessions');
    }
    if (version < 27) {
      await db.customStatement(
        'ALTER TABLE water_profiles DROP COLUMN bicarbonate_ppm',
      );
      await db.customStatement(
        'ALTER TABLE water_profiles DROP COLUMN recipe_json',
      );
    }
    if (version < 26) {
      await db.customStatement(
        'ALTER TABLE coffee_components DROP COLUMN altitude_max_meters',
      );
    }
    if (version < 25) {
      await db.customStatement(
        'ALTER TABLE brews DROP COLUMN frozen_portion_id',
      );
      await db.customStatement(
        'ALTER TABLE brews DROP COLUMN frozen_dose_grams',
      );
    }
    if (version < 24) {
      await db.customStatement(
        'ALTER TABLE app_preferences DROP COLUMN list_options_json',
      );
    }
    if (version < 23) {
      await db.customStatement('ALTER TABLE brews DROP COLUMN is_favorite');
    }
    if (version < 22) {
      // Same DDL as the published schema 20 (drift_schemas/drift_schema_v20.json).
      await db.customStatement('''
        CREATE TABLE "method_tools_legacy" ("id" TEXT NOT NULL,
          "method_id" TEXT NOT NULL REFERENCES brew_methods (id) ON DELETE RESTRICT,
          "name" TEXT NOT NULL, "archived_at_ms" INTEGER NULL,
          PRIMARY KEY ("id"))
      ''');
      await db.customStatement('''
        INSERT INTO method_tools_legacy (id, method_id, name, archived_at_ms)
        SELECT id, COALESCE(method_id, (
          SELECT method_id FROM tool_method_links WHERE tool_id = method_tools.id LIMIT 1
        )), name, archived_at_ms FROM method_tools
      ''');
      await db.customStatement('DROP TABLE tool_method_links');
      await db.customStatement('DROP TABLE method_tools');
      await db.customStatement(
        'ALTER TABLE method_tools_legacy RENAME TO method_tools',
      );
    }
    if (version < 21) {
      for (final column in ['bloom_count', 'pour_count', 'pour_phases_json']) {
        await db.customStatement('ALTER TABLE brews DROP COLUMN $column');
      }
    }
    if (version < 20) {
      await db.customStatement(
        'ALTER TABLE app_preferences DROP COLUMN scale_device_id',
      );
      await db.customStatement(
        'ALTER TABLE app_preferences DROP COLUMN scale_name',
      );
    }
    await db.customStatement('PRAGMA user_version = $version');
  });
  await db.customStatement('PRAGMA foreign_keys = ON');
}
