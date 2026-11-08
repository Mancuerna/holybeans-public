import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/legacy_schema.dart';

const _kinto = 'method-recipient:origami';

/// A schema 32 journal as the 30→31 migration left it: Origami and V60
/// share the Kinto migrated from Origami, and no brew has a jug.
Future<void> _seed(AppDatabase db) async {
  final coffee = await JournalRepository(db)
      .createCoffee(name: 'Coffee', roaster: 'R');
  await db.batch((batch) {
    batch.insertAll(db.recipients, [
      const Recipient(
        isPortafilter: false,
        id: _kinto,
        name: 'Kinto SCS-S02',
        emptyGrams: 179.3,
      ),
      const Recipient(
        isPortafilter: false,
        id: 'manual',
        name: 'Glass',
        emptyGrams: 300,
      ),
      // Only there so the migration has an espresso jug to refuse.
      const Recipient(
        isPortafilter: false,
        id: 'method-recipient:espresso',
        name: 'Cup',
        emptyGrams: 90,
      ),
    ]);
    batch.insertAll(db.brewMethods, [
      for (final (id, category, jug) in [
        ('origami', 'pourover', _kinto),
        ('v60', 'pourover', _kinto),
        ('espresso', 'espresso', 'method-recipient:espresso'),
        ('chemex', 'pourover', 'manual'),
        ('aeropress', 'immersion', null),
      ])
        BrewMethodsCompanion.insert(
          id: id,
          name: id,
          category: Value(category),
          defaultRecipientId: Value(jug),
        ),
    ]);
  });
  for (final (id, method, bq) in <(String, String, Map<String, Object?>?)>[
    ('native-origami', 'origami', null),
    ('native-v60', 'v60', null),
    ('native-espresso', 'espresso', null),
    ('native-chemex', 'chemex', null),
    ('native-aeropress', 'aeropress', null),
    (
      'bq-kinto',
      'origami',
      {'vessel_name': 'Kinto SCS-S02', 'vessel_weight': 179.3},
    ),
    ('bq-none', 'origami', {'vessel_name': '', 'vessel_weight': 0}),
    (
      'bq-other',
      'v60',
      {'vessel_name': 'Hario server', 'vessel_weight': 210.5},
    ),
    ('bq-unnamed', 'aeropress', {'vessel_name': '', 'vessel_weight': 120}),
    ('bq-espresso', 'espresso', {'vessel_name': 'Cup', 'vessel_weight': 90}),
    ('bq-broken', 'origami', null),
  ]) {
    await db
        .into(db.brews)
        .insert(
          BrewsCompanion.insert(
            id: id,
            coffeeId: coffee,
            methodId: Value(method),
            methodName: method,
            beverageGrams: const Value(240),
            brewedAtMs: 1000,
            createdAtMs: 1000,
            updatedAtMs: 2000,
          ),
        );
    if (bq != null || id == 'bq-broken') {
      await db
          .into(db.importRecords)
          .insert(
            ImportRecordsCompanion.insert(
              id: 'record-$id',
              source: 'beanconqueror',
              kind: 'brew',
              externalId: 'external-$id',
              fingerprint: 'f',
              localEntity: const Value('brew'),
              localId: Value(id),
              importedAtMs: 1500,
            ),
          );
      await db
          .into(db.legacyPayloads)
          .insert(
            LegacyPayloadsCompanion.insert(
              importRecordId: 'record-$id',
              rawJson: bq == null ? '{not json' : jsonEncode(bq),
            ),
          );
    }
  }
  // Chosen after the catalog arrived: never replaced.
  await (db.update(db.brews)..where((b) => b.id.equals('native-v60'))).write(
    const BrewsCompanion(
      recipientId: Value('manual'),
      recipientName: Value('Old glass name'),
      recipientGrams: Value(299),
    ),
  );
}

Future<void> _expectJugsBack(AppDatabase db) async {
  final brews = {for (final b in await db.select(db.brews).get()) b.id: b};
  (String, String, double)? jug(String id) => switch (brews[id]!) {
    Brew(:final recipientId?, :final recipientName?, :final recipientGrams?) =>
      (recipientId, recipientName, recipientGrams),
    _ => null,
  };
  expect(jug('native-origami'), (_kinto, 'Kinto SCS-S02', 179.3));
  expect(jug('native-v60'), ('manual', 'Old glass name', 299));
  expect(jug('native-espresso'), isNull);
  expect(jug('native-chemex'), isNull, reason: 'a jug picked in the catalog');
  expect(jug('native-aeropress'), isNull);
  expect(jug('bq-kinto'), (_kinto, 'Kinto SCS-S02', 179.3));
  expect(jug('bq-none'), isNull, reason: 'BeanConqueror names no jug');
  expect(jug('bq-espresso'), isNull);
  expect(jug('bq-broken'), isNull);
  final added = {
    for (final r in await db.select(db.recipients).get())
      if (!{_kinto, 'manual', 'method-recipient:espresso'}.contains(r.id))
        r.name: r,
  };
  expect(added.keys, unorderedEquals(['Hario server', 'aeropress']));
  expect(jug('bq-other'), (added['Hario server']!.id, 'Hario server', 210.5));
  expect(jug('bq-unnamed'), (added['aeropress']!.id, 'aeropress', 120));
  for (final brew in brews.values) {
    expect(brew.beverageGrams, 240);
    expect(brew.updatedAtMs, 2000, reason: 'not an edit');
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'schema 32→33 gives brews saved before the jug catalog their jug',
    () async {
      final dir = await Directory.systemTemp.createTemp('legacy-jugs-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/journal.sqlite');
      var db = AppDatabase.at(file);
      await _seed(db);
      await reconstructLegacySchema(db, 32);
      await db.close();
      db = AppDatabase.at(file);
      addTearDown(db.close);
      await _expectJugsBack(db);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
    // Reopening a file journal can exceed 30 s during the full suite.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'restoring a v30 backup repairs it; a v31 backup stays as it is',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      final current = await JournalBackup(db).exportJson();
      expect(jsonDecode(current)['version'], JournalBackup.version);
      final v31 = jsonDecode(current) as Map<String, dynamic>..['version'] = 31;
      for (final row in v31['data']['preferences'] as List) {
        (row as Map).remove('scalesJson');
      }

      await JournalBackup(db).restoreJson(jsonEncode(v31));
      final untouched = await db.select(db.brews).get();
      expect(untouched.where((b) => b.recipientId != null).map((b) => b.id), [
        'native-v60',
      ]);

      final old = jsonDecode(current) as Map<String, dynamic>;
      old['version'] = 30;
      await JournalBackup(db).restoreJson(jsonEncode(old));
      await _expectJugsBack(db);
    },
  );

  test('an import from BeanConqueror keeps the jug of every brew', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = JournalRepository(db);
    final export = exportJson();
    Map<String, Object?> v60(String id, Object? name, Object? grams) => {
      'config': config(id, DateTime(2025, 1, 6)),
      'bean': 'bean-finished',
      'method_of_preparation': 'prep-v60',
      'grind_weight': 15,
      'brew_quantity': 250,
      'brew_quantity_type': 'GR',
      'brew_beverage_quantity': 210,
      'brew_beverage_quantity_type': 'GR',
      'vessel_name': name,
      'vessel_weight': grams,
    };
    export['BREWS'] = [
      for (final brew in export['BREWS'] as List)
        {...brew as Map, 'vessel_name': 'Cup', 'vessel_weight': 90},
      v60('brew-kinto', 'Kinto SCS-S02', 179.3),
      v60('brew-glass', 'Glass', 300),
      v60('brew-none', '', 0),
    ];
    final plan = planBeanconquerorImport(
      BeanconquerorArchive.read(
        Uint8List.fromList(utf8.encode(jsonEncode(export))),
      ),
      await repository.beanconquerorJournal(),
    );
    await repository.importBeanconqueror(plan);

    final methods = {
      for (final m in await db.select(db.brewMethods).get()) m.name: m,
    };
    final recipients = {
      for (final r in await db.select(db.recipients).get()) r.id: r,
    };
    final kinto = recipients[methods['V60']!.defaultRecipientId]!;
    expect((kinto.name, kinto.emptyGrams), ('Kinto SCS-S02', 179.3));
    final byGrams = <double?, Brew>{
      for (final b in await db.select(db.brews).get()) b.beverageGrams: b,
    };
    expect(byGrams[36.4]!.recipientId, isNull, reason: 'espresso');
    final brews = await db.select(db.brews).get();
    final jugs = {
      for (final b in brews)
        if (b.methodName == 'V60') (b.recipientName, b.recipientGrams),
    };
    expect(jugs, {('Kinto SCS-S02', 179.3), ('Glass', 300.0), (null, null)});
    expect(
      brews.firstWhere((b) => b.recipientName == 'Kinto SCS-S02').recipientId,
      kinto.id,
      reason: "the method's own jug, not a copy",
    );
    expect(recipients.values.map((r) => r.name), contains('Glass'));
    expect(recipients, hasLength(2));
  });
}
