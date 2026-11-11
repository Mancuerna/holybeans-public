import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mixed hardness recipe survives backup and reopens unchanged', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final model = WaterCalculatorModel();
    addTearDown(model.dispose);
    model.ionTargets = false;
    model.mixHardness = true;
    model.calciumPercent.text = '65';
    model.chooseMode(WaterCalculationMode.custom);
    final recipe = model.recipe!;
    await JournalRepository(db)
        .createWaterProfile(name: 'Mixture', recipeJson: recipe.toJson());
    final backup = JournalBackup(db);
    await backup.restoreJson(await backup.exportJson());
    final row = await db.select(db.waterProfiles).getSingle();
    final reopened = WaterCalculatorModel(
      seed: WaterRecipe.fromJson(row.recipeJson!),
    );
    addTearDown(reopened.dispose);
    expect(reopened.calciumPercent.text, '65');
    expect(reopened.recipe!.toJson(), recipe.toJson());
  });
  test('water recipe and bicarbonate survive backup; older profiles remain readable', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final recipe = WaterRecipe(
      litres: 2,
      calcium: CalciumForm.dihydrate,
      mode: WaterCalculationMode.preset,
      base: WaterComposition.distilled(),
      target: WaterPreset.raoPerger.composition,
      presetId: WaterPreset.raoPerger.name,
      grams: WaterPreset.raoPerger
          .gramsPerLitre(CalciumForm.dihydrate)
          .map((s, g) => MapEntry(s, g * 2)),
    );
    await repo.createWaterProfile(
      name: 'Recipe',
      minerals: const WaterMinerals(bicarbonate: 49),
      recipeJson: recipe.toJson(),
    );
    final before = await db.select(db.waterProfiles).getSingle();
    final backup = JournalBackup(db);
    final json = await backup.exportJson();
    expect(jsonDecode(json)['version'], JournalBackup.version);
    await backup.restoreJson(json);
    expect(await db.select(db.waterProfiles).getSingle(), before);
    for (final version in [19, 25]) {
      final old = jsonDecode(json) as Map<String, dynamic>;
      old['version'] = version;
      final profile =
          (old['data']['waterProfiles'] as List<dynamic>).single
              as Map<String, dynamic>;
      profile.remove('bicarbonatePpm');
      profile.remove('recipeJson');
      await backup.restoreJson(jsonEncode(old));
      final row = await db.select(db.waterProfiles).getSingle();
      expect(row.name, 'Recipe');
      expect(row.bicarbonatePpm, isNull);
      expect(row.recipeJson, isNull);
    }
    await backup.restoreJson(json);
    final invalid = jsonDecode(json) as Map<String, dynamic>;
    invalid['data']['waterProfiles'][0]['recipeJson'] = '{"version":999}';
    await expectLater(
      backup.restoreJson(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(await db.select(db.waterProfiles).getSingle(), before);
  });
}
