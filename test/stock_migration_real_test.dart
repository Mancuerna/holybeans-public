import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/legacy_schema.dart';

void main() {
  final path = Platform.environment['HOLYBEANS_STOCK_BACKUP'];
  test(
    'real v27 backup and schema 28 migration preserve every old field',
    () async {
      final original = File(path!).readAsBytesSync();
      final zip = ZipDecoder().decodeBytes(original);
      final source = utf8.decode(
        zip.findFile('holybeans-backup.json')!.content as List<int>,
      );
      final photos = {
        for (final f in zip.files)
          if (f.name.startsWith('photos/')) f.name.substring(7),
      };
      final dir = await Directory.systemTemp.createTemp(
        'holybeans-stock-migration-',
      );
      final file = File('${dir.path}/journal.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await JournalBackup(db).restoreJson(source, availablePhotos: photos);
        final originalData = jsonDecode(source)['data'] as Map<String, dynamic>;
        await reconstructLegacySchema(db, 28);
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        final current =
            jsonDecode(await JournalBackup(db).exportJson())['data']
                as Map<String, dynamic>;
        for (final entry in originalData.entries) {
          final rows = current[entry.key] as List;
          expect(rows.length, (entry.value as List).length, reason: entry.key);
          for (var i = 0; i < rows.length; i++) {
            final a = Map<String, dynamic>.from(rows[i] as Map);
            final b = Map<String, dynamic>.from(entry.value[i] as Map);
            if (entry.key == 'preferences') {
              expect(a.remove('scalesJson'), isNull);
            }
            if (entry.key == 'methods') a.remove('defaultRecipientId');
            if (entry.key == 'brews') {
              a.remove('recipientId');
              a.remove('recipientName');
              a.remove('recipientGrams');
              expect(
                a.remove('stockReviewPending'),
                b['archivedAtMs'] != null && b['archivedByCoffee'] != true
                    ? true
                    : null,
              );
            }
            expect(a, b, reason: '${entry.key} row $i');
          }
        }
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
        final roundtrip = await JournalBackup(db).exportJson();
        await JournalBackup(db).restoreJson(roundtrip, availablePhotos: photos);
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          current,
        );
        expect(File(path).readAsBytesSync(), original);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: path == null
        ? 'Set HOLYBEANS_STOCK_BACKUP to a private real ZIP.'
        : false,
  );
}
