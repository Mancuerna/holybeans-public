import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_alternatives_picker.dart';
import 'package:holybeans/ui/equipment/water_calculator_fields.dart';
import 'package:holybeans/ui/equipment/water_calculator_inputs.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets('automatic GH and selectable doses ($language)', (
      tester,
    ) async {
      final m = WaterCalculatorModel();
      addTearDown(m.dispose);
      m.setSalt(WaterSalt.potassiumBicarbonate, true);
      m.chooseMode(WaterCalculationMode.custom);
      m.mineralWater = true;
      m.baseKh.text = '0';
      m.ions[WaterIon.calcium]!.text = '0';
      m.ions[WaterIon.magnesium]!.text = '0';
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await AppLocalizations.delegate.load(Locale(language));
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(language),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: m,
              builder: (_, _) => SingleChildScrollView(
                child: Column(
                  children: [
                    WaterCalculatorInputs(model: m, savedProfiles: const []),
                    WaterAlternativesPicker(model: m),
                    if (m.recipe != null)
                      WaterCalculatorResult(
                        recipe: m.recipe!,
                        showDerived: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WaterDerivedValues), findsWidgets);
      expect(find.byKey(const ValueKey('water-show-derived')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('water-base-more-ions')),
      );
      await tester.tap(find.byKey(const ValueKey('water-base-more-ions')));
      await tester.pumpAndSettle();
      expect(find.text(s.waterManualGh), findsOneWidget);
      expect(find.text(s.waterManualGhHint), findsOneWidget);
      expect(m.baseGh.text, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('water-alternatives')),
      );
      await tester.tap(find.text(s.waterAlternatives));
      await tester.pumpAndSettle();
      final index = m.alternatives.indexWhere(
        (r) =>
            r.grams[WaterSalt.potassiumBicarbonate]! > 0 &&
            r.grams[WaterSalt.sodiumBicarbonate] == 0,
      );
      final option = find.byKey(ValueKey('water-alternative-$index'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(m.selectedAlternative, index);
      final result = tester.widget<WaterCalculatorResult>(
        find.byType(WaterCalculatorResult),
      );
      expect(result.recipe.grams[WaterSalt.sodiumBicarbonate], 0);
      expect(
        result.recipe.grams[WaterSalt.potassiumBicarbonate],
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
