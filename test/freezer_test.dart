import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUpAll(() async {
    // Every database in this file uses its own in-memory SQLite executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('es');
  });

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('freezer', () {
    Future<(String, String)> coffeeWithLot(double grams) async {
      final coffeeId = await repository.createCoffee(
        name: 'Freezer coffee',
        roaster: 'Test roaster',
        initialGrams: grams,
      );
      final lot = (await repository.coffeeLots(coffeeId)).single;
      return (coffeeId, lot.id);
    }

    test('freezing moves grams out of the unfrozen balance', () async {
      final (coffeeId, lotId) = await coffeeWithLot(250);
      final portionId = await repository.freezeCoffee(
        lotId: lotId,
        grams: 100,
        frozenDate: '2026-09-29',
        container: 'tube',
        notes: '  Weekend  ',
      );
      final portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.id, portionId);
      expect(portion.label, matches(RegExp(r'^[2-9A-HJ-NP-Z]{5}$')));
      expect(portion.initialGrams, 100);
      expect(portion.remainingGrams, 100);
      expect(portion.container, 'tube');
      expect(portion.notes, 'Weekend');
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 150);
      expect(await repository.coffeeStockBalance(coffeeId), 150);
    });

    test('partial and full thawing return grams to the lot', () async {
      final (_, lotId) = await coffeeWithLot(250);
      final portionId = await repository.freezeCoffee(
        lotId: lotId,
        grams: 100,
        frozenDate: '2026-09-29',
      );
      await repository.thawCoffee(portionId, 18);
      var portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.remainingGrams, 82);
      expect(portion.thawedAtMs, isNull);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 168);

      await repository.thawCoffee(portionId, 82);
      portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.remainingGrams, 0);
      expect(portion.thawedAtMs, isNotNull);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 250);
      await expectLater(repository.thawCoffee(portionId, 1), throwsStateError);
    });

    test('freezing is limited by the unfrozen balance', () async {
      final (_, lotId) = await coffeeWithLot(100);
      await expectLater(
        repository.freezeCoffee(
          lotId: lotId,
          grams: 101,
          frozenDate: '2026-09-29',
        ),
        throwsStateError,
      );
      await expectLater(
        repository.freezeCoffee(
          lotId: lotId,
          grams: 10,
          frozenDate: '29/09/2026',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.freezeCoffee(
          lotId: lotId,
          grams: 10,
          frozenDate: '2026-09-29',
          container: 'bucket',
        ),
        throwsArgumentError,
      );
      expect(await repository.frozenPortionsForLot(lotId), isEmpty);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 100);
    });

    test('editing the weight moves only the difference', () async {
      final (_, lotId) = await coffeeWithLot(250);
      final portionId = await repository.freezeCoffee(
        lotId: lotId,
        grams: 100,
        frozenDate: '2026-09-29',
      );
      await repository.thawCoffee(portionId, 30);
      await repository.updateFrozenPortion(
        id: portionId,
        initialGrams: 120,
        frozenDate: '2026-09-28',
        container: 'jar',
      );
      var portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.initialGrams, 120);
      expect(portion.remainingGrams, 90);
      expect(portion.frozenDate, '2026-09-28');
      expect(portion.container, 'jar');
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 160);

      await expectLater(
        repository.updateFrozenPortion(
          id: portionId,
          initialGrams: 20,
          frozenDate: '2026-09-28',
        ),
        throwsStateError,
      );
      portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.initialGrams, 120);
    });

    test('deleting a portion returns what is still frozen', () async {
      final (_, lotId) = await coffeeWithLot(250);
      final portionId = await repository.freezeCoffee(
        lotId: lotId,
        grams: 100,
        frozenDate: '2026-09-29',
      );
      await repository.thawCoffee(portionId, 40);
      await repository.deleteFrozenPortion(portionId);
      expect(await repository.frozenPortionsForLot(lotId), isEmpty);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 250);
    });

    test('backups keep frozen portions and accept older v5 files', () async {
      final (_, lotId) = await coffeeWithLot(250);
      await repository.freezeCoffee(
        lotId: lotId,
        grams: 60,
        frozenDate: '2026-09-29',
        container: 'vacuum_bag',
      );
      final source = await JournalBackup(database).exportJson();
      expect(JournalBackup.inspectJson(source).frozenPortions, 1);

      final restored = memoryDatabase();
      addTearDown(restored.close);
      final summary = await JournalBackup(restored).restoreJson(source);
      expect(summary.frozenPortions, 1);
      final portion = await restored
          .select(restored.frozenPortions)
          .getSingle();
      expect(portion.lotId, lotId);
      expect(portion.remainingGrams, 60);
      expect(portion.container, 'vacuum_bag');

      final legacy = jsonDecode(source) as Map<String, dynamic>;
      legacy['version'] = 5;
      (legacy['data'] as Map<String, dynamic>).remove('frozenPortions');
      final fromV5 = memoryDatabase();
      addTearDown(fromV5.close);
      final legacySummary = await JournalBackup(fromV5)
          .restoreJson(jsonEncode(legacy));
      expect(legacySummary.frozenPortions, 0);
      expect(legacySummary.lots, 1);
    });

    test('a coffee can be added already frozen, fully or in part', () async {
      final frozenId = await repository.createCoffeeWithComponents(
        name: 'Frozen on arrival',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 250,
        freeze: const FreezeRequest(
          grams: 250,
          frozenDate: '2026-09-29',
          container: 'vacuum_bag',
          notes: 'Bottom drawer',
        ),
      );
      final lot = (await repository.coffeeLots(frozenId)).single;
      expect(lot.initialGrams, 250);
      expect(lot.remainingGrams, 0);
      final portion = (await repository.frozenPortionsForLot(lot.id)).single;
      expect(portion.initialGrams, 250);
      expect(portion.container, 'vacuum_bag');
      expect(portion.notes, 'Bottom drawer');

      final partId = await repository.createCoffeeWithComponents(
        name: 'Half frozen',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 250,
        freeze: const FreezeRequest(grams: 200, frozenDate: '2026-09-29'),
      );
      final partLot = (await repository.coffeeLots(partId)).single;
      expect(partLot.remainingGrams, 50);

      await expectLater(
        repository.createCoffeeWithComponents(
          name: 'Too much',
          roaster: 'Test roaster',
          components: const [],
          initialGrams: 100,
          freeze: const FreezeRequest(grams: 150, frozenDate: '2026-09-29'),
        ),
        throwsStateError,
      );
      final names = (await repository.watchCoffees().first).map(
        (coffee) => coffee.name,
      );
      expect(names, isNot(contains('Too much')));
    });

    test('thawing into an empty lot pauses its age', () async {
      final today = DateTime.now();
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Paused',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 250,
        restDays: 21,
        freeze: FreezeRequest(
          grams: 250,
          frozenDate: DateTime(
            today.year,
            today.month,
            today.day - 30,
          ).toIso8601String().substring(0, 10),
        ),
      );
      final coffee = (await repository.watchCoffees().first).single;
      expect(coffee.restDays, 21);
      final lot = (await repository.coffeeLots(coffeeId)).single;
      final portion = (await repository.frozenPortionsForLot(lot.id)).single;
      await repository.thawCoffee(portion.id, 100);
      expect((await repository.coffeeLot(lot.id))!.frozenPauseDays, 30);

      // A lot that still had unfrozen coffee keeps its clock running.
      final otherId = await repository.createCoffee(
        name: 'Running',
        roaster: 'Test roaster',
        initialGrams: 250,
      );
      final otherLot = (await repository.coffeeLots(otherId)).single;
      final otherPortion = await repository.freezeCoffee(
        lotId: otherLot.id,
        grams: 100,
        frozenDate: '2026-09-01',
      );
      await repository.thawCoffee(otherPortion, 50);
      expect(
        (await repository.coffeeLot(otherLot.id))!.frozenPauseDays,
        isNull,
      );
      await expectLater(
        repository.createCoffee(
          name: 'Bad rest',
          roaster: 'Test roaster',
          restDays: -1,
        ),
        throwsArgumentError,
      );
    });

    test('backups reject portions that point at a missing lot', () async {
      final (_, lotId) = await coffeeWithLot(250);
      await repository.freezeCoffee(
        lotId: lotId,
        grams: 60,
        frozenDate: '2026-09-29',
      );
      final backup = jsonDecode(
        await JournalBackup(database).exportJson(),
      ) as Map<String, dynamic>;
      final portions =
          (backup['data'] as Map<String, dynamic>)['frozenPortions'] as List;
      (portions.single as Map<String, dynamic>)['lotId'] = 'missing';
      final target = memoryDatabase();
      addTearDown(target.close);
      await expectLater(
        JournalBackup(target).restoreJson(jsonEncode(backup)),
        throwsFormatException,
      );
    });
  });
}
