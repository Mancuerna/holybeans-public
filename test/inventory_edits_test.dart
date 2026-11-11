import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
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

  test(
    'coffee archive cascade preserves individually archived brews and stock',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Cascade bean',
        roaster: 'Local',
        initialGrams: 100,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      Future<String> brew(double dose) => repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: dose,
      );
      final first = await brew(20);
      final second = await brew(30);
      final individuallyArchived = await brew(10);
      await repository.setBrewArchived(individuallyArchived, archived: true);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        40,
      );

      await repository.setCoffeeArchived(coffeeId, archived: true, rating: 7.5);
      var brews = await database.select(database.brews).get();
      expect(
        brews.singleWhere((row) => row.id == first).archivedByCoffee,
        true,
      );
      expect(
        brews.singleWhere((row) => row.id == second).archivedByCoffee,
        true,
      );
      expect(
        brews
            .singleWhere((row) => row.id == individuallyArchived)
            .archivedByCoffee,
        isNot(true),
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        40,
      );
      expect((await database.select(database.coffees).getSingle()).rating, 7.5);

      await expectLater(
        repository.setBrewArchived(first, archived: false),
        throwsA(isA<BrewArchivedWithCoffeeException>()),
      );
      await expectLater(
        repository.setBrewArchived(individuallyArchived, archived: false),
        throwsA(isA<BrewArchivedWithCoffeeException>()),
      );
      await expectLater(
        repository.createBrew(coffeeId: coffeeId, methodName: 'V60'),
        throwsA(isA<BrewCoffeeArchivedException>()),
      );
      final otherCoffeeId = await repository.createCoffee(
        name: 'Other bean',
        roaster: 'Local',
      );
      final transferCandidate = await repository.createBrew(
        coffeeId: otherCoffeeId,
        methodName: 'V60',
        doseGrams: 5,
      );
      await expectLater(
        repository.saveBrew(
          id: transferCandidate,
          coffeeId: coffeeId,
          methodName: 'V60',
          doseGrams: 5,
        ),
        throwsA(isA<BrewCoffeeArchivedException>()),
      );
      await repository.setBrewArchived(transferCandidate, archived: true);
      await expectLater(
        repository.saveBrew(
          id: transferCandidate,
          coffeeId: coffeeId,
          methodName: 'V60',
          doseGrams: 5,
        ),
        throwsA(isA<BrewCoffeeArchivedException>()),
      );
      await expectLater(
        repository.saveBrew(
          id: first,
          coffeeId: otherCoffeeId,
          methodName: 'V60',
          doseGrams: 20,
        ),
        throwsA(isA<BrewArchivedWithCoffeeException>()),
      );
      await repository.setCoffeeArchived(coffeeId, archived: false);
      await repository.setBrewArchived(first, archived: true);
      await repository.saveBrew(
        id: first,
        coffeeId: otherCoffeeId,
        methodName: 'V60',
        doseGrams: 20,
      );
      final movedBrew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(first))).getSingle();
      expect(movedBrew.coffeeId, otherCoffeeId);
      expect(movedBrew.archivedAtMs, isNotNull);
      expect(movedBrew.archivedByCoffee, false);

      await repository.setCoffeeArchived(coffeeId, archived: false);
      brews = await database.select(database.brews).get();
      expect(
        brews.singleWhere((row) => row.id == first).archivedAtMs,
        isNotNull,
      );
      expect(brews.singleWhere((row) => row.id == second).archivedAtMs, isNull);
      expect(
        brews.singleWhere((row) => row.id == individuallyArchived).archivedAtMs,
        isNotNull,
      );
      expect(
        (await (database.select(
          database.coffeeLots,
        )..where((row) => row.id.equals(lot.id))).getSingle()).remainingGrams,
        60,
      );
      expect(
        (await (database.select(
          database.coffees,
        )..where((row) => row.id.equals(coffeeId))).getSingle()).rating,
        7.5,
      );
    },
  );

  test(
    'negative manual adjustment follows brew creation, edits and restore',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Reduced lot',
        roaster: 'Local',
        initialGrams: 100,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      final firstBrewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 20,
      );
      await setRemainingGrams(database, repository, coffeeId, lot, 60);

      final secondBrewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 10,
      );
      await repository.saveBrew(
        id: firstBrewId,
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 25,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        45,
      );

      await repository.setBrewArchived(firstBrewId, archived: true);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        45,
      );
      await repository.setBrewArchived(firstBrewId, archived: false);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        45,
      );
      await repository.setBrewArchived(secondBrewId, archived: true);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        45,
      );
      await repository.setBrewArchived(secondBrewId, archived: false);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        45,
      );
    },
  );

  test(
    'manual inventory can establish a balance for an unknown purchase total',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Unknown purchase',
        roaster: 'Local',
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 10,
      );
      await setRemainingGrams(database, repository, coffeeId, lot, 40);
      var adjustedLot = await database.select(database.coffeeLots).getSingle();
      expect(adjustedLot.initialGrams, isNull);
      expect(adjustedLot.remainingGrams, 40);

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Unknown purchase',
        roaster: 'Local',
        paidPriceCents: null,
        inventoryLotId: lot.id,
        initialGrams: 100,
        updateOrigin: false,
      );
      adjustedLot = await database.select(database.coffeeLots).getSingle();
      expect(adjustedLot.initialGrams, 100);
      expect(adjustedLot.remainingGrams, 40);

      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 15,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        35,
      );
    },
  );

  test('inventory profile edits preserve recorded consumption', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Editable lot',
      roaster: 'Local',
      roastDate: '2026-09-01',
      initialGrams: 250,
      paidPriceCents: 1200,
    );
    final lot = await database.select(database.coffeeLots).getSingle();
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 18,
    );

    await repository.updateCoffeeProfile(
      id: coffeeId,
      name: 'Editable lot',
      roaster: 'Local',
      paidPriceCents: 1500,
      inventoryLotId: lot.id,
      roastDate: '2026-09-05',
      initialGrams: 500,
      updateOrigin: false,
    );
    var coffee = await database.select(database.coffees).getSingle();
    var updatedLot = await database.select(database.coffeeLots).getSingle();
    expect(coffee.paidPriceCents, 1500);
    expect(updatedLot.roastDate, '2026-09-05');
    expect(updatedLot.initialGrams, 500);
    expect(updatedLot.remainingGrams, 482);
    expect(
      pricePerKgFor(
        paidPriceCents: coffee.paidPriceCents,
        initialGrams: updatedLot.initialGrams,
      ),
      30,
    );

    await repository.updateCoffeeProfile(
      id: coffeeId,
      name: 'Changed name',
      roaster: 'Local',
      paidPriceCents: 2000,
      inventoryLotId: lot.id,
      roastDate: '2026-09-06',
      initialGrams: 10,
      updateOrigin: false,
    );
    coffee = await database.select(database.coffees).getSingle();
    updatedLot = await database.select(database.coffeeLots).getSingle();
    expect(coffee.name, 'Changed name');
    expect(coffee.paidPriceCents, 2000);
    expect(updatedLot.roastDate, '2026-09-06');
    expect(updatedLot.initialGrams, 10);
    expect(updatedLot.remainingGrams, 0);
    expect(updatedLot.overdrawGrams, 8);
  });

  test(
    'legacy unassigned brews are not deducted from a new inventory lot',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Legacy bean',
        roaster: 'Local',
      );
      await database.delete(database.coffeeLots).go();
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        doseGrams: 18,
      );

      await repository.updateCoffeeProfile(
        id: coffeeId,
        name: 'Legacy bean',
        roaster: 'Local',
        paidPriceCents: null,
        createInventoryLot: true,
        roastDate: '2026-09-07',
        initialGrams: 250,
        updateOrigin: false,
      );

      final lot = await database.select(database.coffeeLots).getSingle();
      final brew = await database.select(database.brews).getSingle();
      expect(lot.roastDate, '2026-09-07');
      expect(lot.initialGrams, 250);
      expect(lot.remainingGrams, 250);
      expect(brew.id, brewId);
      expect(brew.lotId, isNull);
    },
  );

  test('profile edits preserve all active and archived lot history', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Multiple lots',
      roaster: 'Local',
      initialGrams: 250,
    );
    final second = CoffeeLot(
      id: 'second-active-lot',
      coffeeId: coffeeId,
      roastDate: '2026-09-10',
      initialGrams: 100,
      remainingGrams: 82,
      createdAtMs: 2,
      updatedAtMs: 3,
    );
    final archived = CoffeeLot(
      id: 'archived-lot',
      coffeeId: coffeeId,
      roastDate: '2026-08-10',
      initialGrams: 200,
      remainingGrams: 0,
      createdAtMs: 1,
      updatedAtMs: 4,
      archivedAtMs: 5,
    );
    await database.batch((batch) {
      batch.insertAll(database.coffeeLots, [second, archived]);
    });
    final before = await database.select(database.coffeeLots).get();

    await repository.updateCoffeeProfile(
      id: coffeeId,
      name: 'Multiple lots renamed',
      roaster: 'Local',
      paidPriceCents: 1800,
      updateOrigin: false,
    );

    expect(await database.select(database.coffeeLots).get(), before);
    expect(
      (await database.select(database.coffees).getSingle()).name,
      'Multiple lots renamed',
    );
  });
}
