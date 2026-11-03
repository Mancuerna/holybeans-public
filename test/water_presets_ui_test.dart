import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_calculator_inputs.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets('select and scale salt recipes with large text ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final model = WaterCalculatorModel();
      addTearDown(model.dispose);
      late AppLocalizations s;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                s = AppLocalizations.of(context)!;
                return AnimatedBuilder(
                  animation: model,
                  builder: (context, _) => ListView(
                    children: [
                      WaterCalculatorInputs(
                        model: model,
                        savedProfiles: const [],
                      ),
                      WaterCalculatorResult(recipe: model.recipe!),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byType(Scrollable).first;
      for (final preset in [
        WaterPreset.holyWater,
        WaterPreset.raoLotus,
        WaterPreset.gwoNoSeaSalt,
        WaterPreset.budapestBh,
      ]) {
        final selector = find.byKey(const ValueKey('water-preset'));
        await tester.drag(scroll, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(selector, 200, scrollable: scroll);
        await tester.pumpAndSettle();
        await tester.tap(selector);
        await tester.pumpAndSettle();
        final option = find.text(presetLabel(s, preset));
        await tester.scrollUntilVisible(
          option,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
        if (model.missingPresetSalts.isNotEmpty) {
          final add = find.byKey(const ValueKey('water-use-recipe-salts'));
          await tester.scrollUntilVisible(add, 150, scrollable: scroll);
          await tester.tap(add);
          await tester.pumpAndSettle();
        }
        expect(model.preset, preset);
        expect(tester.takeException(), isNull);
      }
      model.choosePreset(WaterPreset.holyWater);
      model.litres.text = '5';
      await tester.pumpAndSettle();
      final dose = find.byKey(
        const ValueKey('water-dose-potassiumBicarbonate'),
      );
      await tester.scrollUntilVisible(dose, 180, scrollable: scroll);
      expect(tester.widget<Text>(dose).data, '0.230 g');
      expect(
        find.byKey(const ValueKey('water-dose-sodiumBicarbonate')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
