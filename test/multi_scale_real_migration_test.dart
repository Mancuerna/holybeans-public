import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/legacy_schema.dart';

void main() {
  final backupPath = Platform.environment['HOLYBEANS_SCALES_BACKUP'];
  test(
    'real schema 33 diary migrates with its scale and every collection intact',
    () async {
      final bytes = File(backupPath!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final original =
          (jsonDecode(source) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final dir = await Directory.systemTemp.createTemp(
        'multi-scale-migration-',
      );
      final file = File('${dir.path}/diary.sqlite');
      var db = AppDatabase.at(file);
      try {
        await JournalBackup(db)
            .restoreJson(source, availablePhotos: photos.keys.toSet());
        final legacy = await ScaleSettings(db).load();
        await reconstructLegacySchema(db, 33);
        await db.close();
        db = AppDatabase.at(file);
        final exported = await JournalBackup(db).exportJson();
        final actual =
            (jsonDecode(exported) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        for (final row in actual['preferences'] as List) {
          expect((row as Map).remove('scalesJson'), isNull);
        }
        expect(actual, original);
        final settings = ScaleSettings(db);
        expect((await settings.load())?.deviceId, legacy?.deviceId);
        await settings.save(
          const RememberedScale(
            deviceId: 'second-test-scale',
            name: 'BOOKOO_SC_M',
          ),
        );
        expect(await settings.loadAll(), hasLength(legacy == null ? 1 : 2));
        await settings.forget('second-test-scale');
        expect((await settings.load())?.deviceId, legacy?.deviceId);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA integrity_check').get())
              .single
              .data
              .values
              .single,
          'ok',
        );
        await JournalBackup(db)
            .restoreJson(exported, availablePhotos: photos.keys.toSet());
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          jsonDecode(exported)['data'],
        );
        final (_, savedPhotos) = JournalBackup.readArchive(
          JournalBackup.encodeArchive(exported, photos),
        );
        expect(savedPhotos, photos);
        expect(File(backupPath).readAsBytesSync(), bytes);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    skip: backupPath == null
        ? 'Set HOLYBEANS_SCALES_BACKUP to a real schema 33 backup.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
