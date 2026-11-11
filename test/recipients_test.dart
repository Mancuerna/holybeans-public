import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

import 'helpers/legacy_schema.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'catalog changes do not rewrite a saved tare; explicit clearing does',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(name: 'Coffee', roaster: 'R');
      final jug = await repo.saveRecipient(name: 'Glass', emptyGrams: 200);
      final saved = await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodName: 'V60',
          beverageGrams: 250,
          recipient: RecipientSnapshot(
            id: jug.id,
            name: jug.name,
            grams: jug.emptyGrams,
          ),
        ),
      );
      await repo.saveRecipient(id: jug.id, name: 'Renamed', emptyGrams: 210);
      await repo.setRecipientArchived(jug.id, archived: true);
      var brew = await db.select(db.brews).getSingle();
      expect(brew.recipientName, 'Glass');
      expect(brew.recipientGrams, 200);
      await repo.saveBrew(
        id: brew.id,
        coffeeId: coffee,
        methodName: 'V60',
        beverageGrams: 260,
      );
      brew = await db.select(db.brews).getSingle();
      expect(brew.recipientGrams, 200);
      final backup = await JournalBackup(db).exportJson();
      await JournalBackup(db).restoreJson(backup);
      expect((await db.select(db.brews).getSingle()).toJson(), brew.toJson());
      await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodName: 'V60',
          beverageGrams: 260,
          replaceRecipient: true,
        ),
        id: brew.id,
      );
      expect((await db.select(db.brews).getSingle()).recipientId, isNull);
      expect(saved, isNotNull);
    },
  );

  test(
    'selection recalculates net weight, editing retains historical tare',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(name: 'Coffee', roaster: 'R');
      final method = await repo.createMethod(
        name: 'V60',
        category: 'pourover',
        vesselName: 'Old jug',
        vesselGrams: 200,
      );
      final other = await repo.saveRecipient(
        name: 'Other jug',
        emptyGrams: 150,
      );
      final model = BrewFormModel(
        repository: repo,
        settings: BrewParameterSettings(db),
        coffees: await db.select(db.coffees).get(),
        initialMethodId: method,
      );
      addTearDown(model.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(model.jugGrams, 200);
      model.draft.jugTotal.text = '500';
      expect(model.draft.beverage.text, '300');
      model.selectRecipient(other);
      expect(model.draft.beverage.text, '350');
      model.selectRecipient(null);
      expect(model.draft.beverage.text, '350');
      expect(model.draft.jugTotal.text, isEmpty);
      final outcome = await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodId: method,
          methodName: 'V60',
          beverageGrams: 350,
          recipient: RecipientSnapshot(
            id: other.id,
            name: other.name,
            grams: other.emptyGrams,
          ),
        ),
      );
      expect(outcome, isNotNull);
      final brew = await db.select(db.brews).getSingle();
      await repo.saveRecipient(
        id: other.id,
        name: 'Other jug',
        emptyGrams: 170,
      );
      final edited = BrewFormModel(
        repository: repo,
        settings: BrewParameterSettings(db),
        coffees: await db.select(db.coffees).get(),
        existing: brew,
      );
      addTearDown(edited.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(edited.jugGrams, 150);
      expect(edited.draft.jugTotal.text, '500');
    },
  );

  test(
    'schema 30 and old backup migrate named and unnamed archived jars',
    () async {
      final dir = await Directory.systemTemp.createTemp('recipient-migration-');
      var db = AppDatabase.at(File('${dir.path}/test.sqlite'));
      try {
        final repo = JournalRepository(db);
        final id = await repo.createMethod(
          name: 'V60',
          vesselName: 'Jug',
          vesselGrams: 200,
        );
        final archived = await repo.createMethod(
          name: 'Origami',
          vesselGrams: 180,
        );
        await repo.setMethodArchived(archived, archived: true);
        final raw = jsonDecode(
          await JournalBackup(db).exportJson(),
        ) as Map<String, dynamic>;
        final data = raw['data'] as Map<String, dynamic>;
        data.remove('recipients');
        raw['version'] = 29;
        for (final dynamic method in data['methods'] as List) {
          (method as Map).remove('defaultRecipientId');
        }
        await reconstructLegacySchema(db, 30);
        await db.close();
        db = AppDatabase.at(File('${dir.path}/test.sqlite'));
        final migrated = jsonDecode(
          await JournalBackup(db).exportJson(),
        )['data'];
        final methods = await db.select(db.brewMethods).get();
        expect(
          methods.firstWhere((m) => m.id == id).defaultRecipientId,
          'method-recipient:$id',
        );
        expect(
          (await db.select(db.recipients).get()).map((r) => r.emptyGrams),
          containsAll([200.0, 180.0]),
        );
        expect(
          methods.firstWhere((m) => m.id == archived).archivedAtMs,
          isNotNull,
        );
        await JournalBackup(db).restoreJson(jsonEncode(raw));
        expect(
          jsonDecode(await JournalBackup(db).exportJson())['data'],
          migrated,
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
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'invalid recipient references and incomplete backups fail atomically',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(name: 'Coffee', roaster: 'R');
      await expectLater(
        repo.saveBrewWithOutcome(
          BrewInput(
            coffeeId: coffee,
            methodName: 'V60',
            recipient: const RecipientSnapshot(
              id: 'missing',
              name: 'Jug',
              grams: 200,
            ),
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.brews).get(), isEmpty);
      final before = await JournalBackup(db).exportJson();
      final raw = jsonDecode(before) as Map<String, dynamic>;
      (raw['data'] as Map).remove('recipients');
      await expectLater(
        JournalBackup(db).restoreJson(jsonEncode(raw)),
        throwsFormatException,
      );
      expect((await db.select(db.coffees).getSingle()).id, coffee);
      for (final grams in [0.0, -1.0, double.nan, double.infinity, 10001.0]) {
        await expectLater(
          repo.saveRecipient(name: 'Jug', emptyGrams: grams),
          throwsArgumentError,
        );
      }
    },
  );
}
