import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/journal_test_support.dart';
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

  test('a brew cannot reference a lot owned by another coffee', () async {
    final firstId = await repository.createCoffee(name: 'A', roaster: 'R');
    await repository.createCoffee(name: 'B', roaster: 'R');
    final lots = await database.select(database.coffeeLots).get();
    final otherLot = lots.singleWhere((lot) => lot.coffeeId != firstId);
    await expectLater(
      repository.createBrew(
        coffeeId: firstId,
        lotId: otherLot.id,
        methodName: 'V60',
      ),
      throwsStateError,
    );
    expect(await database.select(database.brews).get(), isEmpty);
  });

  test(
    'stock follows brew creation, editing, bag changes and archiving',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Kieni',
        roaster: 'Loma',
        initialGrams: 250,
      );
      final firstLot = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.coffeeId.equals(coffeeId))).getSingle();
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: firstLot.id,
        methodName: 'V60',
        doseGrams: 18,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        232,
      );

      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        lotId: firstLot.id,
        methodName: 'V60',
        doseGrams: 20,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        230,
      );

      final secondLot = CoffeeLot(
        id: 'second-lot',
        coffeeId: coffeeId,
        initialGrams: 100,
        remainingGrams: 100,
        createdAtMs: 2,
        updatedAtMs: 2,
      );
      await database.into(database.coffeeLots).insert(secondLot);
      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        lotId: secondLot.id,
        methodName: 'V60',
        doseGrams: 20,
      );
      var lots = await database.select(database.coffeeLots).get();
      expect(
        lots.singleWhere((lot) => lot.id == firstLot.id).remainingGrams,
        250,
      );
      expect(
        lots.singleWhere((lot) => lot.id == secondLot.id).remainingGrams,
        80,
      );

      await repository.setBrewArchived(brewId, archived: true);
      lots = await database.select(database.coffeeLots).get();
      expect(
        lots.singleWhere((lot) => lot.id == secondLot.id).remainingGrams,
        80,
      );
      await repository.setBrewArchived(brewId, archived: false);
      expect(
        (await database.select(database.coffeeLots).get())
            .singleWhere((lot) => lot.id == secondLot.id)
            .remainingGrams,
        80,
      );

      await expectLater(
        repository.saveBrew(
          id: brewId,
          coffeeId: coffeeId,
          lotId: secondLot.id,
          methodName: 'V60',
          doseGrams: 120,
        ),
        completes,
      );
      expect(
        (await database.select(database.brews).getSingle()).doseGrams,
        120,
      );
      final overdrawn = (await database.select(database.coffeeLots).get())
          .singleWhere((lot) => lot.id == secondLot.id);
      expect(overdrawn.remainingGrams, 0);
      expect(overdrawn.overdrawGrams, 20);

      await repository.setBrewArchived(brewId, archived: true);
      final restoredByArchive = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.id.equals(secondLot.id))).getSingle();
      expect(restoredByArchive.remainingGrams, 0);
      expect(restoredByArchive.overdrawGrams, 20);
      await repository.setBrewArchived(brewId, archived: false);
      final reapplied = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.id.equals(secondLot.id))).getSingle();
      expect(reapplied.remainingGrams, 0);
      expect(reapplied.overdrawGrams, 20);
      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        lotId: secondLot.id,
        methodName: 'V60',
        doseGrams: 20,
      );
      final editedBack = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.id.equals(secondLot.id))).getSingle();
      expect(editedBack.remainingGrams, 80);
      expect(editedBack.overdrawGrams, 0);
      expect((await database.select(database.brews).getSingle()).doseGrams, 20);
    },
  );

  test('profile weight edits and later purchased quantity edits preserve brew deltas', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Adjusted lot',
      roaster: 'Local',
      initialGrams: 250,
    );
    final lot = await database.select(database.coffeeLots).getSingle();
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 18,
    );

    await setRemainingGrams(database, repository, coffeeId, lot, 300);
    var adjustedLot = await database.select(database.coffeeLots).getSingle();
    expect(adjustedLot.initialGrams, 250);
    expect(adjustedLot.remainingGrams, 300);

    await repository.updateCoffeeProfile(
      id: coffeeId,
      name: 'Adjusted lot',
      roaster: 'Local',
      paidPriceCents: null,
      inventoryLotId: lot.id,
      initialGrams: 200,
      updateOrigin: false,
    );
    adjustedLot = await database.select(database.coffeeLots).getSingle();
    expect(adjustedLot.initialGrams, 200);
    expect(adjustedLot.remainingGrams, 250);
    expect(adjustedLot.remainingGrams, greaterThan(adjustedLot.initialGrams!));

    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 20,
    );
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      248,
    );
    await repository.setBrewArchived(brewId, archived: true);
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      248,
    );
    await repository.setBrewArchived(brewId, archived: false);
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      248,
    );
  });

  test(
    'profile editor sets current weight without changing purchase or price',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Measured remaining weight',
        roaster: 'Local',
        initialGrams: 250,
        paidPriceCents: 1250,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 40,
      );
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 230,
      );

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Measured remaining weight',
        roaster: 'Local',
        paidPriceCents: 1250,
        roastLevel: 'dark',
        updateRoastLevel: true,
        inventoryLotId: lot.id,
        initialGrams: 250,
        remainingGrams: 0,
        updateOrigin: false,
      );
      var storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.remainingGrams, 0);
      expect(storedLot.overdrawGrams, 20);

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Measured remaining weight',
        roaster: 'Local',
        paidPriceCents: 1250,
        inventoryLotId: lot.id,
        initialGrams: 250,
        remainingGrams: 175,
        updateRemainingStock: true,
        updateOrigin: false,
      );

      storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.initialGrams, 250);
      expect(storedLot.remainingGrams, 175);
      expect(storedLot.overdrawGrams, 0);
      expect(
        pricePerKgFor(
          paidPriceCents: 1250,
          initialGrams: storedLot.initialGrams,
        ),
        50,
      );

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Measured remaining weight',
        roaster: 'Local',
        paidPriceCents: 1250,
        inventoryLotId: lot.id,
        initialGrams: 250,
        remainingGrams: 90,
        updateOrigin: false,
      );
      storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.remainingGrams, 175);

      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 15,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        160,
      );
    },
  );

  test(
    'manual adjustment after overdraft resets debt before later brew deltas',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Overdraw adjustment',
        roaster: 'Local',
        initialGrams: 100,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 120,
      );
      var storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.remainingGrams, 0);
      expect(storedLot.overdrawGrams, 20);

      await setRemainingGrams(database, repository, coffeeId, lot, 35);
      storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.remainingGrams, 35);
      expect(storedLot.overdrawGrams, 0);

      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 130,
      );
      storedLot = await database.select(database.coffeeLots).getSingle();
      expect(storedLot.remainingGrams, 25);
      expect(storedLot.overdrawGrams, 0);
    },
  );

  test(
    'overdraw prompt uses known coffee total and leaves unknown stock unknown',
    () async {
      final exactCoffeeId = await repository.createCoffee(
        name: 'Exact stock',
        roaster: 'Local',
        initialGrams: 10,
      );
      final exactLot = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.coffeeId.equals(exactCoffeeId))).getSingle();
      final exactOutcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: exactCoffeeId,
          lotId: exactLot.id,
          methodName: 'V60',
          doseGrams: 10,
        ),
      );
      expect(exactOutcome.overdrawIncreased, isFalse);
      expect(await repository.coffeeStockBalance(exactCoffeeId), 0);
      final exactlyConsumed = await repository.coffeeLot(exactLot.id);
      expect(exactlyConsumed!.remainingGrams, 0);
      expect(exactlyConsumed.overdrawGrams, 0);

      final coffeeId = await repository.createCoffee(
        name: 'Two active lots',
        roaster: 'Local',
        initialGrams: 10,
      );
      final firstLot = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.coffeeId.equals(coffeeId))).getSingle();
      await database
          .into(database.coffeeLots)
          .insert(
            CoffeeLot(
              id: 'second-known-lot',
              coffeeId: coffeeId,
              initialGrams: 100,
              remainingGrams: 100,
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
      final outcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffeeId,
          lotId: firstLot.id,
          methodName: 'V60',
          doseGrams: 15,
        ),
      );
      expect(outcome.overdrawIncreased, isFalse);
      expect(await repository.coffeeStockBalance(coffeeId), 95);

      final editedOutcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffeeId,
          lotId: firstLot.id,
          methodName: 'V60',
          doseGrams: 115,
        ),
        id: outcome.id,
      );
      expect(editedOutcome.overdrawIncreased, isTrue);
      expect(await repository.coffeeStockBalance(coffeeId), -5);

      final unknownCoffeeId = await repository.createCoffee(
        name: 'Unknown stock',
        roaster: 'Local',
      );
      final unknownLot = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.coffeeId.equals(unknownCoffeeId))).getSingle();
      final unknownOutcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: unknownCoffeeId,
          lotId: unknownLot.id,
          methodName: 'V60',
          doseGrams: 100,
        ),
      );
      expect(unknownOutcome.overdrawIncreased, isFalse);
      expect(await repository.coffeeStockBalance(unknownCoffeeId), isNull);
      final stillUnknown = await (database.select(
        database.coffeeLots,
      )..where((lot) => lot.id.equals(unknownLot.id))).getSingle();
      expect(stillUnknown.remainingGrams, isNull);
      expect(stillUnknown.overdrawGrams, isNull);
    },
  );

  test(
    'first purchase total includes brews archived with the coffee',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Archived consumption',
        roaster: 'Local',
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 10,
      );
      await repository.setCoffeeArchived(coffeeId, archived: true);

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Archived consumption',
        roaster: 'Local',
        paidPriceCents: null,
        inventoryLotId: lot.id,
        initialGrams: 5,
        updateOrigin: false,
      );
      final updatedLot = await database.select(database.coffeeLots).getSingle();
      expect(updatedLot.remainingGrams, 0);
      expect(updatedLot.overdrawGrams, 5);
    },
  );
}
