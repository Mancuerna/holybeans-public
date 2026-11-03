import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/legacy_schema.dart';

void main() {
  final path = Platform.environment['HOLYBEANS_ADJUSTMENTS_BACKUP'];
  test(
    'real schema 29 migration preserves all collections and photos',
    () async {
      final bytes = File(path!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final dir = await Directory.systemTemp.createTemp(
        'stock-adjustments-migration-',
      );
      final file = File('${dir.path}/journal.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await JournalBackup(db)
            .restoreJson(source, availablePhotos: photos.keys.toSet());
        final before = jsonDecode(await JournalBackup(db).exportJson())['data'];
        await reconstructLegacySchema(db, 29);
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        final after = jsonDecode(await JournalBackup(db).exportJson())['data'];
        expect(after, before);
        expect(after['stockAdjustments'], isEmpty);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA integrity_check').getSingle())
              .data
              .values
              .single,
          'ok',
        );
        final exported = await JournalBackup(db).exportJson();
        await JournalBackup(db)
            .restoreJson(exported, availablePhotos: photos.keys.toSet());
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          before,
        );
        expect(File(path).readAsBytesSync(), bytes);
        final (_, roundtripPhotos) = JournalBackup.readArchive(
          JournalBackup.encodeArchive(exported, photos),
        );
        expect(roundtripPhotos, photos);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: path == null
        ? 'Set HOLYBEANS_ADJUSTMENTS_BACKUP to a fresh Samsung backup.'
        : false,
  );
}
