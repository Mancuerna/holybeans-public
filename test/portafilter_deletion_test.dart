import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late Recipient portafilter;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    portafilter = await repository.saveRecipient(
      name: 'Trial',
      emptyGrams: 500,
      isPortafilter: true,
    );
  });
  tearDown(() => database.close());

  Matcher blockedBy(EquipmentDeletionBlocker blocker) => throwsA(
    isA<EquipmentInUseException>().having(
      (error) => error.blockers,
      'blockers',
      contains(blocker),
    ),
  );

  for (final archived in [false, true]) {
    test('deletes unused portafilter (archived: $archived)', () async {
      await repository.setRecipientArchived(portafilter.id, archived: archived);
      final other = await repository.saveRecipient(
        name: 'Jug',
        emptyGrams: 200,
      );
      expect(
        await repository.portafilterDeletionBlockers(portafilter.id),
        isEmpty,
      );
      await repository.deleteUnusedPortafilter(portafilter.id);
      expect(
        (await database.select(database.recipients).get()).single.id,
        other.id,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('blocks method added after checking (archived: $archived)', () async {
      expect(
        await repository.portafilterDeletionBlockers(portafilter.id),
        isEmpty,
      );
      final method = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
        defaultRecipientId: portafilter.id,
        useRecipientCatalog: true,
      );
      await repository.setMethodArchived(method, archived: archived);
      expect(await repository.portafilterDeletionBlockers(portafilter.id), [
        EquipmentDeletionBlocker.methods,
      ]);
      await expectLater(
        repository.deleteUnusedPortafilter(portafilter.id),
        blockedBy(EquipmentDeletionBlocker.methods),
      );
      expect(
        (await database.select(database.brewMethods).getSingle())
            .defaultRecipientId,
        portafilter.id,
      );
      await repository.updateMethod(
        id: method,
        name: 'Espresso',
        category: 'espresso',
        useRecipientCatalog: true,
      );
      await repository.deleteUnusedPortafilter(portafilter.id);
      expect(await database.select(database.recipients).get(), isEmpty);
      expect(await database.select(database.brewMethods).get(), hasLength(1));
    });

    test('protects brew and historical tare (archived: $archived)', () async {
      expect(
        await repository.portafilterDeletionBlockers(portafilter.id),
        isEmpty,
      );
      final coffee = await repository.createCoffee(
        name: 'Coffee',
        roaster: 'R',
      );
      final method = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
      await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodId: method,
          methodName: 'Espresso',
          recipient: RecipientSnapshot(
            id: portafilter.id,
            name: portafilter.name,
            grams: portafilter.emptyGrams,
            isPortafilter: true,
          ),
        ),
      );
      final brew = await database.select(database.brews).getSingle();
      await repository.setBrewArchived(brew.id, archived: archived);
      expect(await repository.portafilterDeletionBlockers(portafilter.id), [
        EquipmentDeletionBlocker.brews,
        EquipmentDeletionBlocker.methods,
      ]);
      // Saving a brew remembers the portafilter; remove only that default.
      await repository.updateMethod(
        id: method,
        name: 'Espresso',
        category: 'espresso',
        useRecipientCatalog: true,
      );
      expect(await repository.portafilterDeletionBlockers(portafilter.id), [
        EquipmentDeletionBlocker.brews,
      ]);
      await expectLater(
        repository.deleteUnusedPortafilter(portafilter.id),
        blockedBy(EquipmentDeletionBlocker.brews),
      );
      final retained = await database.select(database.brews).getSingle();
      expect(retained.recipientId, portafilter.id);
      expect(retained.recipientGrams, portafilter.emptyGrams);
      expect(await database.select(database.recipients).get(), hasLength(1));
    });
  }

  test('rejects missing IDs and ordinary vessels', () async {
    await expectLater(
      repository.portafilterDeletionBlockers('missing'),
      throwsStateError,
    );
    await expectLater(
      repository.deleteUnusedPortafilter('missing'),
      throwsStateError,
    );
    final jug = await repository.saveRecipient(name: 'Jug', emptyGrams: 200);
    await expectLater(
      repository.portafilterDeletionBlockers(jug.id),
      throwsArgumentError,
    );
    await expectLater(
      repository.deleteUnusedPortafilter(jug.id),
      throwsArgumentError,
    );
    expect(await database.select(database.recipients).get(), hasLength(2));
  });
}
