import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_calculator_page.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets(
      'saved water, direct ion target, available salts and backup ($locale)',
      (tester) async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        await repo.createWaterProfile(
          name: 'Starting bottle',
          khPpmAsCaCO3: 10,
          minerals: const WaterMinerals(
            calcium: 5,
            magnesium: 2,
            sodium: 0,
            potassium: 0,
            sulfate: 0,
            chloride: 0,
            bicarbonate: 12.192764487660224,
          ),
        );
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final s = await AppLocalizations.delegate.load(Locale(locale));
        Widget harness(Widget child) =>
            localizedApp(locale: Locale(locale), home: child);
        await tester.pumpWidget(harness(WaterCalculatorPage(repository: repo)));
        await tester.pumpAndSettle();
        await tester.runAsync(() => repo.watchWaterProfiles().first);
        await tester.pumpAndSettle();
        Future<void> show(String key) async {
          final finder = find.byKey(ValueKey(key));
          if (finder.evaluate().isEmpty) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 4000),
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          await show(key);
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
        }

        await tap('water-saved-source');
        await tap('water-mode');
        await tester.tap(find.text(s.waterCustomMode).last);
        await tester.pumpAndSettle();
        for (final (key, value) in [
          ('kh', '30'),
          ('calcium', '20'),
          ('magnesium', '5'),
        ]) {
          await show('water-target-$key');
          await tester.enterText(
            find.byKey(ValueKey('water-target-$key')),
            value,
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
        }
        WaterRecipe result() => tester
            .widget<WaterCalculatorResult>(find.byType(WaterCalculatorResult))
            .recipe;
        await show('water-save-result');
        // The result follows the long form in the same scroll view.
        await tester.scrollUntilVisible(
          find.byType(WaterCalculatorResult),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(result().result[WaterIon.calcium], closeTo(20, 1e-8));
        expect(result().result[WaterIon.magnesium], closeTo(5, 1e-8));
        expect(result().result.kh, closeTo(30, 1e-8));
        await tap('water-remove-calciumChloride');
        await tester.scrollUntilVisible(
          find.byType(WaterCalculatorResult),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(result().grams[WaterSalt.calciumChloride], 0);
        expect(result().result[WaterIon.calcium], 5);
        expect(
          find.byKey(const ValueKey('water-unreachable-target')),
          findsOneWidget,
        );
        await tap('water-add-salt');
        await tester.tap(find.text(s.waterSaltCalciumChloride).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('water-save-result')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, s.waterProfileName),
          'My ion target',
        );
        await tester.tap(find.text(s.save).last);
        await tester.pumpAndSettle();
        final backup = JournalBackup(db);
        await tester.runAsync(() async {
          await backup.restoreJson(await backup.exportJson());
        });
        final profile = (await db.select(db.waterProfiles).get()).singleWhere(
          (p) => p.name == 'My ion target',
        );
        final recipe = WaterRecipe.fromJson(profile.recipeJson!);
        expect(recipe.ionTargets, isTrue);
        expect(recipe.target![WaterIon.sodium], isNull);
        expect(recipe.availableSalts, contains(WaterSalt.calciumChloride));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          harness(WaterCalculatorPage(repository: repo, seed: recipe)),
        );
        await tester.pumpAndSettle();
        await show('water-target-calcium');
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('water-target-calcium')),
              )
              .controller!
              .text,
          '20',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
