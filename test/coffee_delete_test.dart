import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  test(
    'deletion removes only unused coffee data and preserves shared photos',
    () async {
      final id = await repository.createCoffee(
        name: 'Mistake',
        roaster: 'Test',
        country: 'Colombia',
        initialGrams: 250,
      );
      final other = await repository.createCoffee(
        name: 'Keep',
        roaster: 'Test',
      );
      final lot = (await repository.coffeeLots(id)).single;
      await repository.freezeCoffee(
        lotId: lot.id,
        grams: 100,
        frozenDate: '2026-10-04',
      );
      // Archived lots and portions belong to the coffee too.
      await (database.update(database.coffeeLots)
            ..where((row) => row.id.equals(lot.id)))
          .write(const CoffeeLotsCompanion(archivedAtMs: Value(1)));
      const exclusive = '00000000-0000-4000-8000-000000000001.jpg';
      const sharedCoffee = '00000000-0000-4000-8000-000000000002.jpg';
      const sharedBrew = '00000000-0000-4000-8000-000000000003.jpg';
      await repository.setCoffeePhotos(id, [
        exclusive,
        sharedCoffee,
        sharedBrew,
      ]);
      await repository.setCoffeePhotos(other, [sharedCoffee]);
      final brew = await repository.createBrew(
        coffeeId: other,
        methodName: 'V60',
      );
      await repository.setBrewPhotos(brew, [sharedBrew]);
      final now = DateTime.now().millisecondsSinceEpoch;
      await database
          .into(database.importRecords)
          .insert(
            ImportRecordsCompanion.insert(
              id: 'import-delete',
              source: 'beanconqueror',
              kind: 'bean',
              externalId: 'external-delete',
              fingerprint: 'fingerprint',
              localEntity: const Value('coffee'),
              localId: Value(id),
              importedAtMs: now,
            ),
          );
      await database
          .into(database.legacyPayloads)
          .insert(
            const LegacyPayloadsCompanion(
              importRecordId: Value('import-delete'),
              rawJson: Value('{}'),
            ),
          );
      final before = await JournalBackup(database).exportJson();
      expect(await repository.deleteUnusedCoffee(id), [exclusive]);
      expect(await repository.coffee(id), isNull);
      expect((await repository.allCoffees()).single.id, other);
      expect((await repository.allBrews()).single.id, brew);
      expect(await repository.coffeePhotos(other), [sharedCoffee]);
      expect(await repository.brewPhotos(brew), [sharedBrew]);
      expect(await database.select(database.coffeeComponents).get(), isEmpty);
      expect(await database.select(database.frozenPortions).get(), isEmpty);
      expect(await database.select(database.importRecords).get(), isEmpty);
      expect(await database.select(database.legacyPayloads).get(), isEmpty);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final target = memoryDatabase();
      try {
        // Current copies restore the original coffee and inventory.
        expect(jsonDecode(before)['version'], JournalBackup.version);
        await JournalBackup(target).restoreJson(before);
        expect(await JournalRepository(target).coffee(id), isNotNull);
        await JournalBackup(target)
            .restoreJson(await JournalBackup(database).exportJson());
        expect(await JournalRepository(target).coffee(id), isNull);
        expect((await JournalRepository(target).allBrews()).single.id, brew);
      } finally {
        await target.close();
      }
    },
  );

  for (final archived in [false, true]) {
    test(
      'a ${archived ? 'archived' : 'active'} brew blocks deletion without changing any data',
      () async {
        final id = await repository.createCoffee(
          name: 'Used',
          roaster: 'Test',
          country: 'Peru',
          initialGrams: 250,
        );
        final brew = await repository.createBrew(
          coffeeId: id,
          methodName: 'V60',
        );
        if (archived) {
          await (database.update(database.brews)
                ..where((row) => row.id.equals(brew)))
              .write(const BrewsCompanion(archivedAtMs: Value(1)));
        }
        final before = await JournalBackup(database).exportJson();
        await expectLater(
          repository.deleteUnusedCoffee(id),
          throwsA(isA<CoffeeHasBrewsException>()),
        );
        expect(
          jsonDecode(await JournalBackup(database).exportJson())['data'],
          jsonDecode(before)['data'],
        );
      },
    );
  }

  test('an archived coffee with no brews can be deleted', () async {
    final id = await repository.createCoffee(
      name: 'Unused archived',
      roaster: 'Test',
    );
    await repository.setCoffeeArchived(id, archived: true);
    await repository.deleteUnusedCoffee(id);
    expect(await repository.coffee(id), isNull);
  });
}
