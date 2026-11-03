import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';

import 'helpers/legacy_schema.dart';

void main() {
  test(
    'schema 31 merges only identical migrated vessels and keeps snapshots',
    () async {
      final dir = await Directory.systemTemp.createTemp('recipient-merge-');
      final file = File('${dir.path}/db.sqlite');
      var db = AppDatabase.at(file);
      try {
        final repo = JournalRepository(db);
        final coffee = await repo.createCoffee(name: 'Coffee', roaster: 'R');
        for (final entry in <(String, String, double)>[
          ('method-recipient:a', 'Kinto', 179.3),
          ('method-recipient:b', 'Kinto', 179.3),
          ('method-recipient:c', 'Kinto', 180),
          ('method-recipient:d', 'Other', 179.3),
          ('manual', 'Kinto', 179.3),
        ]) {
          await db.customStatement(
            'INSERT INTO recipients (id, name, empty_grams) VALUES (?, ?, ?)',
            [entry.$1, entry.$2, entry.$3],
          );
        }
        for (final id in ['a', 'b']) {
          await repo.createMethod(
            name: id,
            category: 'pourover',
            defaultRecipientId: 'method-recipient:$id',
            useRecipientCatalog: true,
          );
        }
        await repo.saveBrewWithOutcome(
          BrewInput(
            coffeeId: coffee,
            methodName: 'b',
            beverageGrams: 250,
            recipient: const RecipientSnapshot(
              id: 'method-recipient:b',
              name: 'Historical name',
              grams: 175,
            ),
          ),
        );
        final before = await JournalBackup(db).exportJson();
        await reconstructLegacySchema(db, 31);
        await db.close();
        db = AppDatabase.at(file);
        final after = await JournalBackup(db).exportJson();
        expect(
          (await db.select(db.recipients).get()).map((r) => r.id),
          unorderedEquals([
            'method-recipient:a',
            'method-recipient:c',
            'method-recipient:d',
            'manual',
          ]),
        );
        expect(
          (await db.select(db.brewMethods).get()).map(
            (m) => m.defaultRecipientId,
          ),
          everyElement('method-recipient:a'),
        );
        final brew = await db.select(db.brews).getSingle();
        expect(brew.recipientId, 'method-recipient:a');
        expect(brew.recipientName, 'Historical name');
        expect(brew.recipientGrams, 175);
        expect(brew.beverageGrams, 250);
        await JournalBackup(db).restoreJson(before);
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          jsonDecode(after)['data'],
        );
        await JournalBackup(db).restoreJson(after);
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          jsonDecode(after)['data'],
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    // Reopening a file journal can exceed 30 s while the real-copy
    // migrations run in parallel in the full suite.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  final backupPath = Platform.environment['HOLYBEANS_RECIPIENT_MERGE_BACKUP'];
  test(
    'real schema 31 copy preserves all data except duplicate IDs',
    () async {
      final bytes = File(backupPath!).readAsBytesSync();
      final (source, photos) = JournalBackup.readArchive(bytes);
      final original = jsonDecode(source)['data'] as Map<String, dynamic>;
      final dir = await Directory.systemTemp.createTemp(
        'recipient-merge-real-',
      );
      var db = AppDatabase.at(File('${dir.path}/db.sqlite'));
      try {
        await JournalBackup(db)
            .restoreJson(source, availablePhotos: photos.keys.toSet());
        final expected = jsonDecode(
          await JournalBackup(db).exportJson(),
        )['data'];
        // Reconstruct the exact pre-fix rows before opening schema 31.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.delete(db.recipients).go();
        for (final row in original['recipients'] as List) {
          await db
              .into(db.recipients)
              .insert(
                Recipient.fromJson(Map<String, dynamic>.from(row as Map)),
              );
        }
        for (final row in original['methods'] as List) {
          final m = row as Map;
          await db.customStatement(
            'UPDATE brew_methods SET default_recipient_id = ? WHERE id = ?',
            [m['defaultRecipientId'], m['id']],
          );
        }
        for (final row in original['brews'] as List) {
          final b = row as Map;
          await db.customStatement(
            'UPDATE brews SET recipient_id = ? WHERE id = ?',
            [b['recipientId'], b['id']],
          );
        }
        await reconstructLegacySchema(db, 31);
        await db.close();
        db = AppDatabase.at(File('${dir.path}/db.sqlite'));
        final exported = await JournalBackup(db).exportJson();
        final actual = jsonDecode(exported)['data'] as Map<String, dynamic>;
        expect(actual, expected);
        expect((actual['recipients'] as List).length, 1);
        for (final entry in original.entries) {
          if (entry.key == 'recipients') continue;
          final rows = actual[entry.key] as List;
          expect(rows.length, (entry.value as List).length);
          for (var i = 0; i < rows.length; i++) {
            final old = Map<String, dynamic>.from(entry.value[i] as Map);
            final now = Map<String, dynamic>.from(rows[i] as Map);
            if (entry.key == 'methods') {
              old.remove('defaultRecipientId');
              now.remove('defaultRecipientId');
            }
            if (entry.key == 'brews') {
              old.remove('recipientId');
              now.remove('recipientId');
              // Schema 33 gives brews back the jug they were weighed in.
              if (old['recipientName'] == null &&
                  now['recipientName'] != null) {
                final jug = (actual['recipients'] as List).single as Map;
                expect(
                  (now.remove('recipientName'), now.remove('recipientGrams')),
                  (jug['name'], jug['emptyGrams']),
                );
                old
                  ..remove('recipientName')
                  ..remove('recipientGrams');
              }
            }
            expect(now, old, reason: '${entry.key}: $i');
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
    timeout: const Timeout(Duration(minutes: 2)),
    skip: backupPath == null
        ? 'Set HOLYBEANS_RECIPIENT_MERGE_BACKUP to the real v30 copy.'
        : false,
  );
}
