import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUpAll(() async {
    // Every database in this file uses its own in-memory SQLite executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('es');
  });

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'brew and coffee ratings accept half steps from zero to ten only',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Rated coffee',
        roaster: 'Local',
      );
      for (final rating in [0.0, 0.5, 10.0]) {
        await repository.createBrew(
          coffeeId: coffeeId,
          methodName: 'V60',
          rating: rating,
        );
        final brew = (await database.select(database.brews).get()).last;
        expect(brew.rating, rating);
        await repository.setCoffeeArchived(
          coffeeId,
          archived: true,
          rating: rating,
        );
        expect(
          (await database.select(database.coffees).getSingle()).rating,
          rating,
        );
        await repository.setCoffeeArchived(coffeeId, archived: false);
      }
      for (final invalid in [0.25, 11.0]) {
        await expectLater(
          repository.createBrew(
            coffeeId: coffeeId,
            methodName: 'V60',
            rating: invalid,
          ),
          throwsArgumentError,
        );
        await expectLater(
          repository.setCoffeeArchived(
            coffeeId,
            archived: true,
            rating: invalid,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('creates a blend with ordered, normalized coffee components', () async {
    final coffeeId = await repository.createCoffeeWithComponents(
      name: '  House Blend  ',
      roaster: '  Roastery  ',
      components: const [
        CoffeeComponentInput(
          country: '  Colombia ',
          region: ' Huila  ',
          variety: ' Caturra ',
          process: ' Washed ',
        ),
        CoffeeComponentInput(
          country: ' Ethiopia ',
          producer: '  Test Farm ',
          altitudeMeters: 1900,
        ),
      ],
      initialGrams: 250,
      paidPriceCents: 1800,
      roastLevel: 'medium',
    );

    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(coffeeId))).getSingle();
    final components = await repository.coffeeComponents(coffeeId);
    final lot = await (database.select(
      database.coffeeLots,
    )..where((row) => row.coffeeId.equals(coffeeId))).getSingle();
    expect(coffee.name, 'House Blend');
    expect(coffee.roaster, 'Roastery');
    expect(coffee.paidPriceCents, 1800);
    expect(lot.initialGrams, 250);
    expect(lot.remainingGrams, 250);
    expect(components, hasLength(2));
    expect(components.map((row) => row.position), [0, 1]);
    expect(components[0].country, 'Colombia');
    expect(components[0].region, 'Huila');
    expect(components[0].variety, 'Caturra');
    expect(components[0].process, 'Washed');
    expect(components[1].country, 'Ethiopia');
    expect(components[1].producer, 'Test Farm');
    expect(components[1].altitudeMeters, 1900);
    expect(components.map((row) => row.id).toSet(), hasLength(2));
  });

  test(
    'every roast level is accepted, omni among them, and nothing else',
    () async {
      for (final level in ['dark', 'medium', 'omni', 'light', 'ultra_light']) {
        final id = await repository.createCoffee(
          name: 'Roast $level',
          roaster: 'R',
          roastLevel: level,
        );
        expect((await repository.coffee(id))!.roastLevel, level);
      }
      expect(
        () => repository.createCoffee(
          name: 'X',
          roaster: 'R',
          roastLevel: 'cinnamon',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'updates blend order and removes components without losing row IDs',
    () async {
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Blend',
        roaster: 'Roastery',
        components: const [
          CoffeeComponentInput(country: 'Kenya', variety: 'SL28'),
          CoffeeComponentInput(country: 'Brazil', process: 'Natural'),
        ],
        initialGrams: 300,
        paidPriceCents: 2100,
      );
      final original = await repository.coffeeComponents(coffeeId);
      final coffee = await database.select(database.coffees).getSingle();

      await repository.updateCoffeeProfileWithComponents(
        id: coffeeId,
        name: coffee.name,
        roaster: coffee.roaster,
        paidPriceCents: coffee.paidPriceCents,
        components: [
          CoffeeComponentInput(
            id: original[1].id,
            country: original[1].country,
            process: original[1].process,
          ),
          CoffeeComponentInput(
            id: original[0].id,
            country: original[0].country,
            variety: 'SL28 and SL34',
          ),
        ],
      );
      var reordered = await repository.coffeeComponents(coffeeId);
      expect(reordered.map((row) => row.id), [original[1].id, original[0].id]);
      expect(reordered.map((row) => row.position), [0, 1]);
      expect(reordered[1].variety, 'SL28 and SL34');

      await repository.updateCoffeeProfileWithComponents(
        id: coffeeId,
        name: coffee.name,
        roaster: coffee.roaster,
        paidPriceCents: coffee.paidPriceCents,
        components: [
          CoffeeComponentInput(
            id: original[1].id,
            country: 'Brazil',
            process: 'Honey',
          ),
          const CoffeeComponentInput(country: 'Guatemala', farm: 'New farm'),
        ],
      );
      reordered = await repository.coffeeComponents(coffeeId);
      expect(reordered, hasLength(2));
      expect(reordered.first.id, original[1].id);
      expect(reordered.first.process, 'Honey');
      expect(reordered.last.id, isNot(original[0].id));
      expect(reordered.last.country, 'Guatemala');

      await repository.updateCoffeeProfileWithComponents(
        id: coffeeId,
        name: coffee.name,
        roaster: coffee.roaster,
        paidPriceCents: coffee.paidPriceCents,
        components: const [],
      );
      expect(await repository.coffeeComponents(coffeeId), isEmpty);
      expect(
        (await database.select(database.coffees).getSingle()).name,
        'Blend',
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      expect(lot.initialGrams, 300);
      expect(lot.remainingGrams, 300);
    },
  );

  test(
    'coffee profile and blend component failures leave all rows unchanged',
    () async {
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Original blend',
        roaster: 'Original roaster',
        components: const [CoffeeComponentInput(country: 'Peru')],
        initialGrams: 250,
        paidPriceCents: 1200,
      );
      final otherCoffeeId = await repository.createCoffeeWithComponents(
        name: 'Other blend',
        roaster: 'Other roaster',
        components: const [CoffeeComponentInput(country: 'Rwanda')],
      );
      final ownComponent = (await repository.coffeeComponents(coffeeId)).single;
      final foreignComponent = (await repository.coffeeComponents(
        otherCoffeeId,
      )).single;
      final lot = await (database.select(
        database.coffeeLots,
      )..where((row) => row.coffeeId.equals(coffeeId))).getSingle();

      await expectLater(
        repository.updateCoffeeProfileWithComponents(
          id: coffeeId,
          name: 'Must roll back',
          roaster: 'Changed roaster',
          paidPriceCents: 9999,
          components: [
            CoffeeComponentInput(id: foreignComponent.id, country: 'Rwanda'),
          ],
          inventoryLotId: lot.id,
          initialGrams: 500,
          remainingGrams: 400,
          updateRemainingStock: true,
        ),
        throwsStateError,
      );
      final storedCoffee = await (database.select(
        database.coffees,
      )..where((row) => row.id.equals(coffeeId))).getSingle();
      expect(storedCoffee.name, 'Original blend');
      expect(storedCoffee.roaster, 'Original roaster');
      expect(storedCoffee.paidPriceCents, 1200);
      final storedLot = await (database.select(
        database.coffeeLots,
      )..where((row) => row.id.equals(lot.id))).getSingle();
      expect(storedLot.initialGrams, 250);
      expect(storedLot.remainingGrams, 250);
      expect(
        (await repository.coffeeComponents(coffeeId)).single.id,
        ownComponent.id,
      );

      await expectLater(
        repository.updateCoffeeProfileWithComponents(
          id: coffeeId,
          name: 'Must stay original',
          roaster: 'Still changed',
          paidPriceCents: -1,
          components: const [CoffeeComponentInput(country: 'Chile')],
        ),
        throwsArgumentError,
      );
      expect(
        (await (database.select(
          database.coffees,
        )..where((row) => row.id.equals(coffeeId))).getSingle()).name,
        'Original blend',
      );

      await expectLater(
        repository.createCoffeeWithComponents(
          name: 'Invalid blend',
          roaster: 'Roastery',
          components: const [CoffeeComponentInput(country: '   ')],
        ),
        throwsArgumentError,
      );
      expect(
        await (database.select(
          database.coffees,
        )..where((row) => row.name.equals('Invalid blend'))).get(),
        isEmpty,
      );
    },
  );

  test('favourites and flavour profiles are stored and normalized', () async {
    final id = await repository.createCoffeeWithComponents(
      name: 'Tasty',
      roaster: 'Test roaster',
      components: const [],
      flavorProfile: ' nectarine ,  jasmine,, Nectarine , honey ',
    );
    var coffee = (await repository.watchCoffees().first).single;
    expect(coffee.flavorProfile, 'nectarine, jasmine, honey');
    expect(coffee.isFavorite, isFalse);

    await repository.setCoffeeFavorite(id, favorite: true);
    await repository.updateCoffeeProfileWithComponents(
      id: id,
      name: 'Tasty',
      roaster: 'Test roaster',
      paidPriceCents: null,
      components: const [],
      flavorProfile: ' , ',
      updateFlavorProfile: true,
    );
    coffee = (await repository.watchCoffees().first).single;
    expect(coffee.isFavorite, isTrue);
    expect(coffee.flavorProfile, isNull);

    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    backup['version'] = 7;
    for (final row
        in (backup['data'] as Map<String, dynamic>)['coffees'] as List) {
      (row as Map<String, dynamic>)
        ..remove('isFavorite')
        ..remove('flavorProfile');
    }
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(jsonEncode(backup));
    final restored = await target.select(target.coffees).getSingle();
    expect(restored.isFavorite, isFalse);
    expect(restored.flavorProfile, isNull);
  });
}
