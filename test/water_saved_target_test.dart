import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const target = WaterProfile(
    id: 'goal',
    name: 'My water',
    calciumPpm: 20,
    magnesiumPpm: 5,
    khPpmAsCaCO3: 30,
  );

  test('saved target uses profile composition, new base and volume', () {
    final m = WaterCalculatorModel();
    addTearDown(m.dispose);
    m.useWater(
      const WaterProfile(
        id: 'base',
        name: 'Bottle',
        calciumPpm: 5,
        magnesiumPpm: 2,
        khPpmAsCaCO3: 10,
      ),
    );
    m.useTarget(
      WaterProfile(
        id: target.id,
        name: target.name,
        calciumPpm: target.calciumPpm,
        magnesiumPpm: target.magnesiumPpm,
        khPpmAsCaCO3: target.khPpmAsCaCO3,
        recipeJson: m.recipe!.toJson(),
      ),
    );
    expect(m.savedBaseId, 'base');
    expect(m.savedTargetId, 'goal');
    expect(m.recipe!.target!.ions[WaterIon.sodium], isNull);
    expect(m.recipe!.result[WaterIon.calcium], closeTo(20, .001));
    expect(m.recipe!.result[WaterIon.magnesium], closeTo(5, .001));
    expect(m.recipe!.result.kh, closeTo(30, .001));
    final grams = m.recipe!.grams;
    m.litres.text = '3';
    for (final salt in WaterSalt.values) {
      expect(m.recipe!.grams[salt], closeTo(grams[salt]! * 3, 1e-8));
    }
    expect(m.recipe!.presetId, isNull);
    expect(m.missingPresetSalts, isEmpty);
    m.choosePreset(WaterPreset.holyWater);
    expect(m.isSavedTarget, isFalse);
    expect(m.recipe!.presetId, WaterPreset.holyWater.name);
  });

  test(
    'incomplete target blocks saving and GH/KH-only targets keep unknown ions',
    () {
      final m = WaterCalculatorModel();
      addTearDown(m.dispose);
      m.useTarget(
        const WaterProfile(id: 'missing', name: 'Incomplete', tdsPpm: 100),
      );
      expect(m.recipe, isNull);
      expect(m.missingTarget, isTrue);
      m.useTarget(
        const WaterProfile(
          id: 'hardness',
          name: 'GH/KH',
          ghPpmAsCaCO3: 80,
          khPpmAsCaCO3: 40,
        ),
      );
      expect(m.missingTarget, isFalse);
      expect(m.recipe!.target![WaterIon.calcium], isNull);
      expect(m.recipe!.result.gh, closeTo(80, .001));
      expect(m.recipe!.result.kh, closeTo(40, .001));
      m.useWater(
        const WaterProfile(
          id: 'hardbase',
          name: 'Hard base',
          ghPpmAsCaCO3: 150,
          khPpmAsCaCO3: 70,
        ),
      );
      expect(m.recipe!.result.gh, greaterThan(m.recipe!.target!.gh!));
      expect(m.recipe!.grams.values, everyElement(0));
      m.useTarget(target);
      expect(m.recipe, isNull);
      expect(m.missingMixtureBase, isTrue);
    },
  );

  test(
    'saved target snapshot survives backup and deletion of its source',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final sourceId = await repo.createWaterProfile(
        name: 'Source',
        khPpmAsCaCO3: 30,
        minerals: const WaterMinerals(calcium: 20, magnesium: 5),
      );
      final source = await db.select(db.waterProfiles).getSingle();
      final m = WaterCalculatorModel();
      addTearDown(m.dispose);
      m.useTarget(source);
      final recipe = m.recipe!;
      await repo.createWaterProfile(
        name: 'Derived',
        recipeJson: recipe.toJson(),
      );
      expect(
        await (db.select(
          db.waterProfiles,
        )..where((t) => t.id.equals(sourceId))).getSingle(),
        source,
      );
      await (db.delete(
        db.waterProfiles,
      )..where((t) => t.id.equals(sourceId))).go();
      final backup = JournalBackup(db);
      await backup.restoreJson(await backup.exportJson());
      final row = await db.select(db.waterProfiles).getSingle();
      final reopened = WaterCalculatorModel(
        seed: WaterRecipe.fromJson(row.recipeJson!),
      );
      addTearDown(reopened.dispose);
      expect(reopened.isSavedTarget, isTrue);
      expect(reopened.targetSelection, 'saved-target');
      expect(reopened.recipe!.target!.toMap(), recipe.target!.toMap());
      for (final salt in WaterSalt.values) {
        expect(
          reopened.recipe!.grams[salt],
          closeTo(recipe.grams[salt]!, 1e-8),
        );
      }
    },
  );
}
