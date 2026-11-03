import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_calculator_inputs.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets('saved waters appear in the existing target menu ($language)', (
      tester,
    ) async {
      final m = WaterCalculatorModel();
      addTearDown(m.dispose);
      final s = await AppLocalizations.delegate.load(Locale(language));
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: m,
              builder: (_, _) => SingleChildScrollView(
                child: WaterCalculatorInputs(
                  model: m,
                  savedProfiles: const [
                    WaterProfile(
                      id: 'my-water',
                      name: 'My saved water',
                      calciumPpm: 20,
                      magnesiumPpm: 5,
                      khPpmAsCaCO3: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('water-preset'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('My saved water').hitTestable(),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text(s.waterMyTargets), findsOneWidget);
      await tester.tap(find.text('My saved water').last);
      await tester.pumpAndSettle();
      expect(m.isSavedTarget, isTrue);
      expect(m.recipe!.target![WaterIon.calcium], 20);
      expect(m.recipe!.result[WaterIon.magnesium], closeTo(5, .001));
      expect(find.text('My saved water'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('water-use-recipe-salts')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
