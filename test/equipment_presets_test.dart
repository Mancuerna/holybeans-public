import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fromEquipment in [true, false]) {
    test(
      'equipment preset from ${fromEquipment ? "equipment" : "a new brew"} survives memory, archive and restore',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final r = JournalRepository(db);
        final coffee = await r.createCoffee(name: 'Coffee', roaster: 'A');
        final method = await r.createMethod(name: 'V60');
        final grinder = await r.createGrinder(name: 'Hand grinder');
        final water = await r.createWaterProfile(name: 'Soft water');
        final filter = await r.createMethodTool(
          methodId: method,
          name: 'Paper',
        );
        final seed = await r.createBrew(
          coffeeId: coffee,
          methodName: 'V60',
          methodId: method,
        );
        final id = await r.presets.create(
          name: 'Morning',
          methodId: method,
          grinderId: grinder,
          waterProfileId: water,
          toolIds: {filter},
        );
        final details = await r.presets.get(id);
        expect(details.uses, 0);
        final model = BrewFormModel(
          services: AppServices.forJournal(
            r,
            parameterSettings: BrewParameterSettings(db),
          ),
          coffees: await r.allCoffees(),
          seed: fromEquipment ? null : await r.brew(seed),
          initialPreset: fromEquipment ? details : null,
        );
        addTearDown(model.dispose);
        Future<void> settle() async {
          for (var i = 0; i < 300 && model.busy; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(model.busy, isFalse);
        }

        await settle();
        if (!fromEquipment) model.selectPreset(details);
        model.selectCoffee(coffee);
        await settle();
        expect(model.selectedToolIds, {filter});
        expect(model.grinderId, grinder);
        expect(model.waterProfileId, water);
        expect((await r.presets.get(id)).uses, 0);
        final brewId = (await model.save())!.id;
        expect((await r.brew(brewId))!.equipmentPresetId, id);
        await r.setBrewArchived(brewId, archived: true);
        final backup = JournalBackup(db);
        await backup.restoreJson(await backup.exportJson());
        expect((await r.presets.get(id)).uses, 1);
        expect(await r.brewToolIds(brewId), [filter]);
        await expectLater(
          r.presets.delete(id),
          throwsA(isA<EquipmentInUseException>()),
        );
      },
    );
  }

  test('unused presets delete only their combination; incompatible tools roll back creation', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final r = JournalRepository(db);
    final m = await r.createMethod(name: 'V60');
    final other = await r.createMethod(name: 'Espresso');
    final t = await r.createMethodTool(methodId: m, name: 'Paper');
    await expectLater(
      r.presets.create(name: 'Wrong filter', methodId: other, toolIds: {t}),
      throwsStateError,
    );
    final id = await r.presets.create(
      name: 'Filter',
      methodId: m,
      toolIds: {t},
    );
    expect(
      await r.methodDeletionBlockers(m),
      contains(EquipmentDeletionBlocker.presets),
    );
    await r.presets.delete(id);
    expect(await r.presets.watch().first, isEmpty);
    expect((await r.toolCatalog()).forMethod(m).single.id, t);
  });
}
