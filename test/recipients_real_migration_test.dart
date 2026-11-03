import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/legacy_schema.dart';

void main() {
  final path = Platform.environment['HOLYBEANS_RECIPIENTS_BACKUP'];
  test(
    'real schema 30 diary preserves every old field and photo after migration',
    () async {
      final bytes = File(path!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final original = jsonDecode(source)['data'] as Map<String, dynamic>;
      final dir = await Directory.systemTemp.createTemp('recipients-real-');
      var db = AppDatabase.at(File('${dir.path}/diary.sqlite'));
      try {
        await JournalBackup(db)
            .restoreJson(source, availablePhotos: photos.keys.toSet());
        final restored = jsonDecode(
          await JournalBackup(db).exportJson(),
        )['data'];
        await reconstructLegacySchema(db, 30);
        await db.close();
        db = AppDatabase.at(File('${dir.path}/diary.sqlite'));
        final exported = await JournalBackup(db).exportJson();
        final actual = jsonDecode(exported)['data'] as Map<String, dynamic>;
        expect(actual, restored);
        for (final entry in original.entries) {
          final rows = actual[entry.key] as List;
          expect(rows.length, (entry.value as List).length, reason: entry.key);
          for (var i = 0; i < rows.length; i++) {
            final row = Map<String, dynamic>.from(rows[i] as Map);
            if (entry.key == 'preferences') {
              expect(row.remove('scalesJson'), isNull);
            }
            if (entry.key == 'methods') row.remove('defaultRecipientId');
            if (entry.key == 'brews') {
              // Schema 33 gives brews back the jug they were weighed in.
              final id = row.remove('recipientId');
              final name = row.remove('recipientName');
              final grams = row.remove('recipientGrams');
              if (id != null) {
                final jug = (actual['recipients'] as List).singleWhere(
                  (r) => r['id'] == id,
                );
                expect((name, grams), (jug['name'], jug['emptyGrams']));
              }
            }
            expect(row, entry.value[i], reason: '${entry.key} row $i');
          }
        }
        final recipients = await db.select(db.recipients).get();
        for (final m in await db.select(db.brewMethods).get()) {
          if (m.vesselGrams == null) {
            expect(m.defaultRecipientId, isNull);
            continue;
          }
          final r = recipients.singleWhere((r) => r.id == m.defaultRecipientId);
          expect(r.emptyGrams, m.vesselGrams);
          expect(
            r.name,
            m.vesselName?.trim().isNotEmpty == true ? m.vesselName : m.name,
          );
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
        await JournalBackup(db)
            .restoreJson(exported, availablePhotos: photos.keys.toSet());
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          actual,
        );
        final (_, savedPhotos) = JournalBackup.readArchive(
          JournalBackup.encodeArchive(exported, photos),
        );
        expect(savedPhotos, photos);
        expect(File(path).readAsBytesSync(), bytes);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: path == null
        ? 'Set HOLYBEANS_RECIPIENTS_BACKUP to a real v29 backup.'
        : false,
  );
}
