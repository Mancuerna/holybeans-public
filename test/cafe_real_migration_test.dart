import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/roaster_profile.dart';

import 'helpers/legacy_schema.dart';

void main() {
  final backup = Platform.environment['HOLYBEANS_CAFE_BACKUP'];
  test(
    'real schema 34 diary gains links with every existing row and photo intact',
    () async {
      final bytes = File(backup!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final original =
          (jsonDecode(source) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final dir = await Directory.systemTemp.createTemp('cafe-migration-');
      final file = File('${dir.path}/diary.sqlite');
      var db = AppDatabase.at(file);
      try {
        await JournalBackup(db)
            .restoreJson(source, availablePhotos: photos.keys.toSet());
        await reconstructLegacySchema(db, 34);
        await db.close();
        db = AppDatabase.at(file);
        final exported = await JournalBackup(db).exportJson();
        final actual =
            (jsonDecode(exported) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        for (final key in original.keys) {
          expect(actual[key], original[key], reason: key);
        }
        final coffees = await db.select(db.coffees).get();
        final links = await db.select(db.coffeeRoasterLinks).get();
        final roasters = await db.select(db.roasters).get();
        expect(
          links.length,
          coffees.where((c) => roasterKey(c.roaster).isNotEmpty).length,
        );
        for (final link in links) {
          expect(
            roasters.firstWhere((r) => r.id == link.roasterId).nameKey,
            roasterKey(
              coffees.firstWhere((c) => c.id == link.coffeeId).roaster,
            ),
          );
        }
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
          (jsonDecode(await JournalBackup(db).exportJson()) as Map)['data'],
          actual,
        );
        expect(
          JournalBackup.readArchive(
            JournalBackup.encodeArchive(exported, photos),
          ).$2,
          photos,
        );
        expect(File(backup).readAsBytesSync(), bytes);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    skip: backup == null
        ? 'Set HOLYBEANS_CAFE_BACKUP to an external real backup.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
