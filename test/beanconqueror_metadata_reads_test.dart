import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/beanconqueror/bq_flow_profile.dart';

import 'helpers/beanconqueror_fixture.dart';

class _PayloadReads extends QueryInterceptor {
  int characters = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    for (final row in rows) {
      for (final column in ['notes', 'samples_json']) {
        if (row[column] case final String text) characters += text.length;
      }
    }
    return rows;
  }
}

void main() {
  test(
    'import preparation reads metadata without notes or curve samples',
    () async {
      final reads = _PayloadReads();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(reads),
      );
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final notes = 'n' * 4096;
      await db.batch((batch) {
        batch.insertAll(db.coffees, [
          for (final id in ['edited', 'unchanged', 'local'])
            CoffeesCompanion.insert(
              id: id,
              name: id,
              roaster: 'Test',
              notes: Value(notes),
              createdAtMs: 1,
              updatedAtMs: id == 'unchanged' ? 10 : 20,
            ),
        ]);
        batch.insertAll(db.brews, [
          for (final id in ['brew-edited', 'brew-unchanged'])
            BrewsCompanion.insert(
              id: id,
              coffeeId: 'edited',
              methodName: 'V60',
              notes: Value(notes),
              brewedAtMs: 1,
              createdAtMs: 1,
              updatedAtMs: id == 'brew-edited' ? 20 : 10,
            ),
        ]);
        batch.insertAll(db.importRecords, [
          for (final id in [
            'edited',
            'unchanged',
            'brew-edited',
            'brew-unchanged',
          ])
            ImportRecordsCompanion.insert(
              id: 'import-$id',
              source: 'beanconqueror',
              kind: id.startsWith('brew-') ? 'brew' : 'bean',
              externalId: 'external-$id',
              fingerprint: 'fingerprint-$id',
              localId: Value(id),
              importedAtMs: 10,
            ),
          ImportRecordsCompanion.insert(
            id: 'other-source',
            source: 'other',
            kind: 'bean',
            externalId: 'external-local',
            fingerprint: 'other',
            localId: const Value('local'),
            importedAtMs: 10,
          ),
        ]);
        batch.insert(
          db.brewMethods,
          BrewMethod(id: 'method', name: ' V60 ', notes: notes),
        );
        batch.insert(
          db.grinders,
          GrindersCompanion.insert(
            id: 'grinder',
            name: ' MILL ',
            notes: Value(notes),
          ),
        );
        batch.insert(
          db.waterProfiles,
          WaterProfile(id: 'water', name: ' WATER ', notes: notes),
        );
        batch.insertAll(db.coffeePhotos, [
          for (var i = 0; i < 2; i++)
            CoffeePhoto(
              coffeeId: 'edited',
              position: i,
              fileName: 'coffee-$i.jpg',
            ),
        ]);
        batch.insert(
          db.brewPhotos,
          const BrewPhoto(
            brewId: 'brew-edited',
            position: 0,
            fileName: 'brew.jpg',
          ),
        );
        batch.insert(
          db.brewCurves,
          BrewCurve(
            brewId: 'brew-edited',
            source: 'beanconqueror',
            samplesJson: jsonEncode(bqFlowCurve(v60FlowProfile())!.toJson()),
          ),
        );
        batch.insert(
          db.coffeeLots,
          CoffeeLotsCompanion.insert(
            id: 'lot',
            coffeeId: 'edited',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
        batch.insert(
          db.frozenPortions,
          FrozenPortion(
            id: 'portion',
            lotId: 'lot',
            label: 'A1',
            frozenDate: '2026-11-01',
            initialGrams: 20,
            remainingGrams: 20,
            notes: notes,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
      });
      reads.characters = 0;
      final journal = await repo.beanconquerorJournal();
      stdout.writeln('IMPORT_METADATA_PAYLOAD_CHARACTERS ${reads.characters}');
      expect(journal.editedHere, {'edited', 'brew-edited'});
      expect(journal.methodsByName, {'v60': 'method'});
      expect(journal.grindersByName, {'mill': 'grinder'});
      expect(journal.watersByName, {'water': 'water'});
      expect(journal.frozenLabels, {'A1'});
      expect(journal.withCurves, {'brew-edited'});
      expect(journal.withPhotos, {'edited', 'brew-edited'});
      expect(journal.imported, {
        'bean': {
          'external-edited': 'edited',
          'external-unchanged': 'unchanged',
        },
        'brew': {
          'external-brew-edited': 'brew-edited',
          'external-brew-unchanged': 'brew-unchanged',
        },
      });
      expect(journal.fingerprints['bean'], {
        'external-edited': 'fingerprint-edited',
        'external-unchanged': 'fingerprint-unchanged',
      });
      expect(reads.characters, 0);
    },
  );
}
