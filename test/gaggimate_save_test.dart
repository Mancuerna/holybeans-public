import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/gaggimate/binary.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

import 'helpers/gaggimate_fixture.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'changing provider clears a pending machine recording before saving',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(name: 'C', roaster: 'R');
      final gm = await repo.createMethod(
        name: 'Gaggia',
        category: 'espresso',
        machine: 'gaggimate',
        machineAddress: 'gaggimate.local',
      );
      final other = await repo.createMethod(
        name: 'Manual',
        category: 'espresso',
      );
      final model = BrewFormModel(
        repository: repo,
        settings: BrewParameterSettings(db),
        coffees: await repo.allCoffees(),
        initialCoffeeId: coffee,
        initialMethodId: gm,
      );
      addTearDown(model.dispose);
      for (var i = 0; i < 100 && model.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      model.applyGaggimateShot(
        decodeGaggimateShot(
          gaggimateLog(),
          id: '31',
          machineAddress: 'http://gaggimate.local',
        ),
      );
      expect(model.importedGaggimateShot, isNotNull);
      await model.selectMethod(other);
      expect(model.importedGaggimateShot, isNull);
      model.applyShot(
        MeticulousShot(
          id: 'old',
          brewedAt: DateTime(2026),
          profileName: 'Other',
        ),
      );
      await model.selectMethod(gm);
      expect(model.importedShot, isNull);
    },
  );

  test(
    'Gaggimate save, replacement, backup and deletion keep provenance coherent',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final method = await repo.createMethod(
        name: 'Gaggia',
        category: 'espresso',
        machine: 'gaggimate',
        machineAddress: 'gaggimate.local',
      );
      final coffee = await repo.createCoffee(
        name: 'Coffee',
        roaster: 'Roaster',
      );
      final shot = decodeGaggimateShot(
        gaggimateLog(),
        id: '31',
        machineAddress: 'http://gaggimate.local',
      );
      final saved = await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodId: method,
          methodName: 'Gaggia',
          doseGrams: 18,
          beverageGrams: shot.yieldGrams,
          timeSeconds: shot.timeSeconds,
        ),
        gaggimateShot: shot,
      );
      expect(await repo.importedGaggimateShots(), {shot.externalId});
      expect(await repo.importedMeticulousShots(), isEmpty);
      expect((await repo.brewCurve(saved.id))!.source, 'gaggimate');
      final restored = memoryDatabase();
      addTearDown(restored.close);
      await JournalBackup(restored)
          .restoreJson(await JournalBackup(db).exportJson());
      final copy = JournalRepository(restored);
      expect((await copy.allMethods()).single.machine, 'gaggimate');
      expect(await copy.importedGaggimateShots(), {shot.externalId});
      expect((await copy.brewCurve(saved.id))!.curve.weight.last, 36.5);
      await repo.attachMeticulousShot(
        saved.id,
        MeticulousShot(id: 'm', brewedAt: DateTime(2026), profileName: 'Other'),
      );
      expect(await repo.importedGaggimateShots(), isEmpty);
      expect(await repo.importedMeticulousShots(), {'m'});
      expect(await repo.brewCurve(saved.id), isNull);
      await repo.attachGaggimateShot(saved.id, shot);
      expect(await repo.importedMeticulousShots(), isEmpty);
      await repo.deleteBrew(saved.id);
      expect(await repo.importedGaggimateShots(), isEmpty);
      expect(await repo.brewCurve(saved.id), isNull);
    },
  );
}
