import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/legacy_schema.dart';

/// The owner's journal of 16 October 2026, as schema 31 left it: the Origami
/// and V60 brews weighed in the Kinto since 10 September lost their jug.
void main() {
  final path = Platform.environment['HOLYBEANS_JUG_BACKUP'];
  test(
    'a real schema 32 journal gets back exactly the jugs it lost',
    () async {
      final bytes = File(path!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final asSaved = jsonDecode(source) as Map<String, dynamic>
        // As a current backup, so restoring it repairs nothing.
        ..['version'] = JournalBackup.version;
      final dir = await Directory.systemTemp.createTemp('jugs-real-');
      final file = File('${dir.path}/diary.sqlite');
      var db = AppDatabase.at(file);
      try {
        await JournalBackup(db).restoreJson(
          jsonEncode(asSaved),
          availablePhotos: photos.keys.toSet(),
        );
        final before =
            jsonDecode(await JournalBackup(db).exportJson())['data']
                as Map<String, dynamic>;
        await reconstructLegacySchema(db, 32);
        await db.close();
        db = AppDatabase.at(file);
        final after =
            jsonDecode(await JournalBackup(db).exportJson())['data']
                as Map<String, dynamic>;

        for (final key in before.keys) {
          if (key != 'brews') expect(after[key], before[key], reason: key);
        }
        final kinto = (before['recipients'] as List).single as Map;
        final methods = {
          for (final m in before['methods'] as List) m['id']: m['name'],
        };
        final since = DateTime(2026, 9, 9).millisecondsSinceEpoch;
        final oldBrews = before['brews'] as List;
        final newBrews = after['brews'] as List;
        expect(newBrews, hasLength(oldBrews.length));
        var given = 0;
        for (var i = 0; i < oldBrews.length; i++) {
          final old = Map<String, dynamic>.from(oldBrews[i] as Map);
          final now = Map<String, dynamic>.from(newBrews[i] as Map);
          final lostJug =
              {'Origami S', 'V60'}.contains(methods[old['methodId']]) &&
              (old['brewedAtMs'] as int) >= since &&
              old['recipientId'] == null;
          if (lostJug) {
            given++;
            expect(now['recipientId'], kinto['id']);
            expect(now['recipientName'], kinto['name']);
            expect(now['recipientGrams'], kinto['emptyGrams']);
            for (final key in [
              'recipientId',
              'recipientName',
              'recipientGrams',
            ]) {
              now.remove(key);
              old.remove(key);
            }
          }
          expect(now, old, reason: 'brew ${old['id']}');
        }
        expect(given, 36);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(File(path).readAsBytesSync(), bytes);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: path == null
        ? 'Set HOLYBEANS_JUG_BACKUP to an external real schema 32 backup.'
        : false,
  );
}
