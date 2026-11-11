import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/database/journal_indexes.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';

const _lookups = {
  'coffee_photo_file_lookup': (
    'SELECT file_name FROM coffee_photos WHERE file_name = ?',
    ['fixture'],
  ),
  'brew_photo_file_lookup': (
    'SELECT file_name FROM brew_photos WHERE file_name = ?',
    ['fixture'],
  ),
  'brew_lot_lookup': ('SELECT id FROM brews WHERE lot_id = ?', ['fixture']),
  'brew_method_lookup': (
    'SELECT id FROM brews WHERE method_id = ?',
    ['fixture'],
  ),
  'brew_water_lookup': (
    'SELECT id FROM brews WHERE water_profile_id = ?',
    ['fixture'],
  ),
  'brew_frozen_portion_lookup': (
    'SELECT id FROM brews WHERE frozen_portion_id = ?',
    ['fixture'],
  ),
  'import_record_entity_lookup': (
    'SELECT id FROM import_records WHERE local_entity = ? AND local_id = ?',
    ['brew', 'fixture'],
  ),
  'coffee_lot_coffee_lookup': (
    'SELECT id FROM coffee_lots WHERE coffee_id = ?',
    ['fixture'],
  ),
  'frozen_portion_lot_lookup': (
    'SELECT id FROM frozen_portions WHERE lot_id = ?',
    ['fixture'],
  ),
  'tool_method_lookup': (
    'SELECT tool_id FROM tool_method_links WHERE method_id = ?',
    ['fixture'],
  ),
};

Future<Map<String, String>> _plans(AppDatabase db) async {
  final plans = <String, String>{};
  for (final entry in _lookups.entries) {
    final (query, values) = entry.value;
    final rows = await db
        .customSelect(
          'EXPLAIN QUERY PLAN $query',
          variables: [for (final value in values) Variable<String>(value)],
        )
        .get();
    plans[entry.key] = rows.map((row) => row.read<String>('detail')).join('; ');
  }
  return plans;
}

void _expectIndexed(Map<String, String> plans) {
  for (final entry in plans.entries) {
    expect(entry.value, allOf(contains('SEARCH'), contains(entry.key)));
  }
}

void main() {
  test('journal lookups use indexes and installation is idempotent', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final plans = await _plans(db);
    stdout.writeln('JOURNAL_LOOKUP_PLANS ${jsonEncode(plans)}');
    _expectIndexed(plans);
    await installJournalIndexes(db);
    expect(await _plans(db), plans);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      AppDatabase.currentSchema,
    );
  });

  test(
    'opening an existing journal installs indexes without changing rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'holybeans-indexes-',
      );
      final file = File(path.join(directory.path, 'journal.sqlite'));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      await db
          .into(db.coffees)
          .insert(
            CoffeesCompanion.insert(
              id: 'existing',
              name: 'Existing',
              roaster: 'Test',
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
      final saved = await db.select(db.coffees).getSingle();
      for (final name in _lookups.keys) {
        await db.customStatement('DROP INDEX IF EXISTS $name');
      }
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      _expectIndexed(await _plans(db));
      expect(await db.select(db.coffees).getSingle(), saved);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        AppDatabase.currentSchema,
      );
    },
  );
}
