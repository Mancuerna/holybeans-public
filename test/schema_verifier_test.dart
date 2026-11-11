import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';

import 'generated_migrations/schema.dart';
import 'helpers/legacy_schema.dart';
import 'helpers/test_database.dart';

/// Migrations are checked against the schemas dumped from the commits that
/// shipped them (`drift_schemas/`), not against a layout rebuilt from today's
/// tables. Schema 20 is the one published in the Play beta.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the latest dump matches the current tables', () async {
    final db = AppDatabase.forTesting(
      await verifier.startAt(AppDatabase.currentSchema),
    );
    addTearDown(db.close);
    expect(db.schemaVersion, AppDatabase.currentSchema);
    await db.validateDatabaseSchema();
  });

  for (final from in [
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
  ]) {
    test(
      'dumped schema $from migrates to exactly the current schema',
      () async {
        final db = AppDatabase.forTesting(await verifier.startAt(from));
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, AppDatabase.currentSchema);
      },
    );
  }

  // Tests and Patrol rebuild old journals from today's tables with
  // reconstructLegacySchema; a schema change that forgets it would make them
  // test a layout that never shipped (as schema 29 once did in Patrol).
  for (final version in [
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
  ]) {
    test('rebuilt schema $version has the dumped tables and columns', () async {
      final dumped = await verifier.schemaAt(version);
      final expected = <String, Set<String>>{
        for (final table in dumped.rawDatabase.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        ))
          table['name'] as String: {
            for (final column in dumped.rawDatabase.select(
              'PRAGMA table_info("${table['name']}")',
            ))
              column['name'] as String,
          },
      };
      final db = memoryDatabase();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await reconstructLegacySchema(db, version);
      final rebuilt = <String, Set<String>>{};
      for (final table
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%'",
              )
              .get()) {
        final name = table.read<String>('name');
        rebuilt[name] = {
          for (final column
              in await db.customSelect('PRAGMA table_info("$name")').get())
            column.read<String>('name'),
        };
      }
      expect(rebuilt, expected);
    });
  }

  test('published schema 20 keeps tools, owners and selections', () async {
    final schema = await verifier.schemaAt(20);
    schema.rawDatabase.execute('''
      INSERT INTO brew_methods (id, name) VALUES ('m1', 'V60'), ('m2', 'Kalita');
      INSERT INTO method_tools (id, method_id, name, archived_at_ms)
        VALUES ('t1', 'm1', 'Paper', NULL), ('t2', 'm2', 'Old filter', 5);
      INSERT INTO coffees (id, name, roaster, created_at_ms, updated_at_ms)
        VALUES ('c1', 'Existing', 'Roaster', 1, 1);
      INSERT INTO brews (id, coffee_id, method_name, method_id, brewed_at_ms,
          created_at_ms, updated_at_ms, bloom_seconds)
        VALUES ('b1', 'c1', 'V60', 'm1', 2, 2, 2, 45);
      INSERT INTO brew_tool_selections (brew_id, tool_id) VALUES ('b1', 't1');
    ''');
    final db = AppDatabase.forTesting(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchema);

    final tools = await (db.select(
      db.methodTools,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(tools.map((t) => (t.id, t.methodId, t.name, t.archivedAtMs)), [
      ('t1', 'm1', 'Paper', null),
      ('t2', 'm2', 'Old filter', 5),
    ]);
    expect(tools.every((t) => t.mergedIntoId == null), isTrue);
    final links = await db.select(db.toolMethodLinks).get();
    expect(links.map((l) => (l.toolId, l.methodId)).toSet(), {
      ('t1', 'm1'),
      ('t2', 'm2'),
    });
    final selection = await db.select(db.brewToolSelections).getSingle();
    expect((selection.brewId, selection.toolId), ('b1', 't1'));
    final brew = await db.select(db.brews).getSingle();
    expect(brew.bloomSeconds, 45);
    expect(
      [brew.bloomCount, brew.pourCount, brew.pourPhasesJson],
      [null, null, null],
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test(
    'schema 22 brings back the favourites marked in BeanConqueror',
    () async {
      final schema = await verifier.schemaAt(22);
      String payload(
        String brew, {
        bool favourite = false,
        bool best = false,
      }) =>
          '''
        INSERT INTO import_records (id, source, kind, external_id, fingerprint,
            local_entity, local_id, imported_at_ms)
          VALUES ('r-$brew', 'beanconqueror', 'brew', 'x-$brew', 'f', 'brew',
            '$brew', 1);
        INSERT INTO legacy_payloads (import_record_id, raw_json)
          VALUES ('r-$brew', '{"favourite": $favourite, "best_brew": $best}');
        ''';
      schema.rawDatabase.execute('''
      INSERT INTO brew_methods (id, name) VALUES ('v60', 'V60'), ('esp', 'Espresso');
      INSERT INTO coffees (id, name, roaster, created_at_ms, updated_at_ms)
        VALUES ('c1', 'Kenya', 'Roaster', 1, 1);
      INSERT INTO brews (id, coffee_id, method_name, method_id, rating,
          brewed_at_ms, created_at_ms, updated_at_ms)
        VALUES ('old', 'c1', 'V60', 'v60', 9, 1, 1, 1),
               ('new', 'c1', 'V60', 'v60', 7, 2, 2, 2),
               ('best', 'c1', 'Espresso', 'esp', 6, 3, 3, 3),
               ('liked', 'c1', 'Espresso', 'esp', 9, 4, 4, 4),
               ('plain', 'c1', 'Espresso', 'esp', 10, 5, 5, 5),
               ('local', 'c1', 'V60', 'v60', 10, 6, 6, 6);
      ${payload('old', favourite: true)}
      ${payload('new', favourite: true)}
      ${payload('best', best: true)}
      ${payload('liked', favourite: true)}
      ${payload('plain')}
    ''');
      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, AppDatabase.currentSchema);

      final favorites = await (db.select(
        db.brews,
      )..where((brew) => brew.isFavorite.equals(true))).get();
      // One per coffee and method: the best brew first, then the best rated;
      // brews never marked in BeanConqueror stay as they were.
      expect(favorites.map((brew) => brew.id).toSet(), {'old', 'best'});
    },
  );

  test(
    'schema 23 keeps its preferences, with the list options unset',
    () async {
      final schema = await verifier.schemaAt(23);
      schema.rawDatabase.execute('''
      INSERT INTO app_preferences (id, share_fields_json, locale_code,
          scale_device_id, scale_name)
        VALUES (1, '["dose"]', 'es', 'EA:54', 'BOOKOO_SC_U');
    ''');
      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, AppDatabase.currentSchema);

      final row = await db.select(db.appPreferences).getSingle();
      expect(
        (
          row.shareFieldsJson,
          row.localeCode,
          row.scaleName,
          row.listOptionsJson,
        ),
        ('["dose"]', 'es', 'BOOKOO_SC_U', null),
      );
    },
  );
}
