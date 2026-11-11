import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/database/journal_write_gate.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
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
    test('deletes unused methods and waters (archived: $archived)', () async {
      final method = await repository.createMethod(name: 'Test method');
      final water = await repository.createWaterProfile(name: 'Test water');
      await repository.setMethodArchived(method, archived: archived);
      await repository.setWaterProfileArchived(water, archived: archived);
      expect(await repository.methodDeletionBlockers(method), isEmpty);
      expect(await repository.waterProfileDeletionBlockers(water), isEmpty);

      await repository.deleteUnusedMethod(method);
      await repository.deleteUnusedWaterProfile(water);

      expect(await database.select(database.brewMethods).get(), isEmpty);
      expect(await database.select(database.waterProfiles).get(), isEmpty);
    });

    test(
      'blocks brews even after a clean check (archived: $archived)',
      () async {
        final method = await repository.createMethod(name: 'V60');
        final water = await repository.createWaterProfile(name: 'Water');
        expect(await repository.methodDeletionBlockers(method), isEmpty);
        expect(await repository.waterProfileDeletionBlockers(water), isEmpty);
        final coffee = await repository.createCoffee(
          name: 'Coffee',
          roaster: 'R',
        );
        final brew = await repository.createBrew(
          coffeeId: coffee,
          methodName: 'V60',
          methodId: method,
          waterProfileId: water,
        );
        await repository.setBrewArchived(brew, archived: archived);

        await expectLater(
          repository.deleteUnusedMethod(method),
          blockedBy(EquipmentDeletionBlocker.brews),
        );
        await expectLater(
          repository.deleteUnusedWaterProfile(water),
          blockedBy(EquipmentDeletionBlocker.brews),
        );
        expect((await repository.brew(brew))!.methodId, method);
        expect((await repository.brew(brew))!.waterProfileId, water);
        expect(await database.select(database.brewMethods).get(), hasLength(1));
        expect(
          await database.select(database.waterProfiles).get(),
          hasLength(1),
        );
      },
    );
  }

  test(
    'blocks archived accessories and allows deletion after unlinking',
    () async {
      final method = await repository.createMethod(name: 'V60');
      final tool = await repository.createTool(
        name: 'Filter',
        methodIds: [method],
      );
      await repository.setMethodToolArchived(tool, archived: true);
      await expectLater(
        repository.deleteUnusedMethod(method),
        blockedBy(EquipmentDeletionBlocker.tools),
      );
      await repository.dissociateTool(tool, method);
      await repository.deleteUnusedMethod(method);
      expect(
        (await database.select(database.methodTools).get()).single.id,
        tool,
      );
    },
  );

  test(
    'protects legacy accessory ownership without a compatibility link',
    () async {
      final method = await repository.createMethod(name: 'Imported method');
      await database
          .into(database.methodTools)
          .insert(
            MethodToolsCompanion.insert(
              id: 'legacy-tool',
              name: 'Imported tool',
              methodId: Value(method),
              archivedAtMs: const Value(1),
            ),
          );
      await expectLater(
        repository.deleteUnusedMethod(method),
        blockedBy(EquipmentDeletionBlocker.tools),
      );
      expect(await database.select(database.methodTools).get(), hasLength(1));
    },
  );

  test(
    'protects machine links even though their foreign key cascades',
    () async {
      final method = await repository.createMethod(name: 'Machine');
      await database
          .into(database.pistonMachines)
          .insert(PistonMachinesCompanion.insert(serial: 'test-serial'));
      await database
          .into(database.pistonMethodLinks)
          .insert(PistonMethodLink(methodId: method, serial: 'test-serial'));
      await expectLater(
        repository.deleteUnusedMethod(method),
        blockedBy(EquipmentDeletionBlocker.machine),
      );
      expect(
        await database.select(database.pistonMethodLinks).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.pistonMachines).get(),
        hasLength(1),
      );
    },
  );

  test(
    'requires removing the default vessel link and preserves the vessel',
    () async {
      final method = await repository.createMethod(
        name: 'V60',
        vesselName: 'Server',
        vesselGrams: 200,
      );
      await expectLater(
        repository.deleteUnusedMethod(method),
        blockedBy(EquipmentDeletionBlocker.recipient),
      );
      await repository.updateMethod(
        id: method,
        name: 'V60',
        useRecipientCatalog: true,
      );
      await repository.deleteUnusedMethod(method);
      expect(await database.select(database.recipients).get(), hasLength(1));
    },
  );

  for (final selection in ['common', 'cup', 'retained cup']) {
    test('protects cupping $selection water without brews', () async {
      final water = await repository.createWaterProfile(name: 'Cupping water');
      final draft = CuppingDraft();
      if (selection == 'common') {
        draft.waterProfileId = water;
      } else {
        draft.cups.first.waterProfileId = water;
        draft.cups.first.commonWater = selection == 'retained cup';
      }
      final session = await repository.createCuppingSession(draft);
      await expectLater(
        repository.deleteUnusedWaterProfile(water),
        blockedBy(EquipmentDeletionBlocker.cupping),
      );
      expect(
        (await repository.cuppingSession(session))!.draftJson,
        draft.toJson(),
      );
      await repository.discardCuppingDraft(session);
      await repository.deleteUnusedWaterProfile(water);
      expect(await database.select(database.waterProfiles).get(), isEmpty);
    });
  }

  test('unrelated cupping sessions do not prevent water deletion', () async {
    final used = await repository.createWaterProfile(name: 'Used');
    final unused = await repository.createWaterProfile(name: 'Unused');
    await repository.createCuppingSession(
      CuppingDraft()..waterProfileId = used,
    );
    await repository.deleteUnusedWaterProfile(unused);
    expect(
      (await database.select(database.waterProfiles).get()).single.id,
      used,
    );
  });

  test(
    'completed cupping retains its water after all brews are deleted',
    () async {
      final water = await repository.createWaterProfile(name: 'Cupping water');
      final coffee = await repository.createCoffee(
        name: 'Coffee',
        roaster: 'R',
        initialGrams: 100,
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      final draft =
          CuppingDraft(
              cups: [
                for (var i = 0; i < 2; i++)
                  CuppingCupDraft(coffeeId: coffee, lotId: lot)
                    ..rating = 8
                    ..scores = [1, 2, 3, 4, 5],
              ],
            )
            ..waterProfileId = water
            ..startedAtMs = 1000
            ..brokenAtMs = 301000
            ..tastingAtMs = 601000
            ..phase = CuppingPhase.tasting;
      final session = await repository.createCuppingSession(draft);
      final brews = await repository.finishCupping(session, draft);
      for (final brew in brews) {
        await repository.deleteBrew(brew);
      }
      expect(await database.select(database.brews).get(), isEmpty);
      await expectLater(
        repository.deleteUnusedWaterProfile(water),
        blockedBy(EquipmentDeletionBlocker.cupping),
      );
      expect(
        (await repository.cuppingSession(session))!.completedAtMs,
        isNotNull,
      );
    },
  );

  test('failed deletion rolls back import provenance cleanup', () async {
    final method = await repository.createMethod(name: 'Imported');
    await database
        .into(database.importRecords)
        .insert(
          ImportRecordsCompanion.insert(
            id: 'import',
            source: 'test',
            kind: 'method',
            externalId: 'source',
            fingerprint: 'test',
            importedAtMs: 1,
            localEntity: const Value('method'),
            localId: Value(method),
          ),
        );
    await database
        .into(database.legacyPayloads)
        .insert(
          LegacyPayloadsCompanion.insert(
            importRecordId: 'import',
            rawJson: '{}',
          ),
        );
    await database.customStatement('''
      CREATE TRIGGER reject_method_delete BEFORE DELETE ON brew_methods
      BEGIN SELECT RAISE(ABORT, 'simulated failure'); END
    ''');
    await expectLater(repository.deleteUnusedMethod(method), throwsException);
    expect(await database.select(database.brewMethods).get(), hasLength(1));
    expect(await database.select(database.importRecords).get(), hasLength(1));
    expect(await database.select(database.legacyPayloads).get(), hasLength(1));
  });

  test('unknown IDs fail without changing the catalog', () async {
    await repository.createMethod(name: 'Keep');
    await repository.createWaterProfile(name: 'Keep');
    await expectLater(
      repository.deleteUnusedMethod('missing'),
      throwsStateError,
    );
    await expectLater(
      repository.deleteUnusedWaterProfile('missing'),
      throwsStateError,
    );
    expect(await database.select(database.brewMethods).get(), hasLength(1));
    expect(await database.select(database.waterProfiles).get(), hasLength(1));
  });

  for (final entity in ['method', 'water']) {
    test('$entity deletion removes only its own import provenance', () async {
      final id = entity == 'method'
          ? await repository.createMethod(name: 'Imported')
          : await repository.createWaterProfile(name: 'Imported');
      for (final record in ['remove', 'keep']) {
        await database
            .into(database.importRecords)
            .insert(
              ImportRecordsCompanion.insert(
                id: record,
                source: 'test',
                kind: entity,
                externalId: record,
                fingerprint: 'test',
                importedAtMs: 1,
                localEntity: Value(entity),
                localId: Value(record == 'remove' ? id : 'other'),
              ),
            );
        await database
            .into(database.legacyPayloads)
            .insert(
              LegacyPayloadsCompanion.insert(
                importRecordId: record,
                rawJson: '{}',
              ),
            );
      }
      if (entity == 'method') {
        await repository.deleteUnusedMethod(id);
      } else {
        await repository.deleteUnusedWaterProfile(id);
      }
      expect(
        (await database.select(database.importRecords).get()).single.id,
        'keep',
      );
      expect(
        (await database.select(database.legacyPayloads).get())
            .single
            .importRecordId,
        'keep',
      );
    });
  }

  test('deletion respects the journal write gate', () async {
    final method = await repository.createMethod(name: 'Keep');
    final water = await repository.createWaterProfile(name: 'Keep');
    database.writeGate.writable = false;
    await expectLater(
      repository.deleteUnusedMethod(method),
      throwsA(isA<JournalReadOnlyException>()),
    );
    await expectLater(
      repository.deleteUnusedWaterProfile(water),
      throwsA(isA<JournalReadOnlyException>()),
    );
    expect(await database.select(database.brewMethods).get(), hasLength(1));
    expect(await database.select(database.waterProfiles).get(), hasLength(1));
  });
}
