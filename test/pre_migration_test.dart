// Real journal files on disk: slow when the whole suite writes at once.
@Tags(['slow'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/pre_migration.dart';

import 'helpers/legacy_schema.dart';

void main() {
  test('the schema comes from the SQLite header', () {
    final header = [
      ...ascii.encode('SQLite format 3'),
      0,
      ...List.filled(84, 0),
    ];
    header[63] = 22;
    expect(sqliteUserVersion(header), 22);
    header[62] = 1;
    expect(sqliteUserVersion(header), 256 + 22);
    expect(sqliteUserVersion(header.sublist(0, 99)), isNull);
    expect(sqliteUserVersion(List.filled(100, 0)), isNull);
  });

  test('only an older, existing schema is worth a copy', () {
    bool needs(int? schema) =>
        needsPreMigrationCopy(fileSchema: schema, currentSchema: 23);
    expect(needs(22), isTrue);
    expect(needs(19), isTrue);
    expect(needs(23), isFalse, reason: 'already up to date');
    expect(needs(24), isFalse, reason: 'newer files are not opened');
    expect(needs(0), isFalse, reason: 'a new journal');
    expect(needs(null), isFalse, reason: 'not SQLite');
  });

  test('copies are named by schema and time, newest first', () {
    final name = PreMigrationCopy.nameFor(
      22,
      DateTime.utc(2026, 10, 5, 13, 2, 26),
    );
    expect(name, 'holybeans-schema22-20261005T130226Z.sqlite');
    final copy = PreMigrationCopy.parse(name)!;
    expect(
      (copy.schema, copy.savedAt),
      (22, DateTime.utc(2026, 10, 5, 13, 2, 26)),
    );
    expect(
      PreMigrationCopy.parse('holybeans-schema22-20261305T130226Z.sqlite'),
      isNull,
      reason: 'month 13',
    );
    expect(
      preMigrationCopies([
        PreMigrationCopy.nameFor(20, DateTime.utc(2026, 10, 2)),
        '$name-journal',
        PreMigrationCopy.nameFor(21, DateTime.utc(2026, 10, 4)),
        'notes.txt',
        name,
      ]).map((copy) => copy.schema),
      [22, 21, 20],
    );
  });

  group('on the phone', () {
    late Directory folder;
    late File journal;
    late PreMigrationCopies copies;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('pre-migration-test-');
      journal = File('${folder.path}/holybeans.sqlite');
      copies = PreMigrationCopies(Directory('${folder.path}/pre-migration'));
    });

    tearDown(() => folder.delete(recursive: true));

    /// A journal with one coffee, left in schema [schema] as an older app
    /// would have left it.
    Future<void> journalAt(int schema) async {
      final database = AppDatabase.at(journal);
      await JournalRepository(database)
          .createCoffee(name: 'Kenya', roaster: 'R');
      if (schema < AppDatabase.currentSchema) {
        await reconstructLegacySchema(database, schema);
      }
      await database.close();
    }

    Future<PreMigrationCopy?> keep(DateTime now) => copies.keepIfUpgrading(
      journal,
      currentSchema: AppDatabase.currentSchema,
      now: now,
    );

    test('an older journal is copied before it opens, and comes back '
        'up to date', () async {
      await journalAt(22);
      final copy = await keep(DateTime.utc(2026, 10, 5, 13));
      expect(copy?.schema, 22);
      expect(await copies.list(), hasLength(1));
      // Opening the journal upgrades it; the copy stays at 22.
      final opened = AppDatabase.at(journal);
      await opened.select(opened.coffees).get();
      await opened.close();
      expect(await keep(DateTime.utc(2026, 10, 5, 14)), isNull);
      final header = await copies.file(copy!).openRead(0, 100).first;
      expect(sqliteUserVersion(header), 22);

      final source = await copies.exportJson(copy);
      final data = (jsonDecode(source) as Map)['data'] as Map;
      expect((data['coffees'] as List).single['name'], 'Kenya');
      expect(
        sqliteUserVersion(await copies.file(copy).openRead(0, 100).first),
        22,
        reason: 'restoring works on a temporary copy',
      );
    });

    test('nothing is copied for a new or current journal, and only the '
        'newest copies are kept', () async {
      expect(await keep(DateTime.utc(2026, 10, 5)), isNull, reason: 'no file');
      await journalAt(AppDatabase.currentSchema);
      expect(await keep(DateTime.utc(2026, 10, 5)), isNull);

      await journal.delete();
      await journalAt(20);
      for (var day = 1; day <= preMigrationCopiesKept + 2; day++) {
        await keep(DateTime.utc(2026, 10, day));
      }
      final kept = await copies.list();
      expect(kept, hasLength(preMigrationCopiesKept));
      expect(
        kept.first.savedAt,
        DateTime.utc(2026, 10, preMigrationCopiesKept + 2),
      );
    });

    test('a file that is not a journal is left alone', () async {
      await journal.writeAsString('not a database');
      expect(await keep(DateTime.utc(2026, 10, 5)), isNull);
      expect(await copies.list(), isEmpty);
    });
  });
}
