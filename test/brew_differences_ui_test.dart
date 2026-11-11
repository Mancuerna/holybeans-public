import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/brew_comparison.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/ui/brews/brew_differences_summary.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    for (final method in ['Espresso', 'V60']) {
      testWidgets(
        'differences at 320px large text $language $method respect hidden fields',
        (tester) async {
          final db = memoryDatabase();
          addTearDown(db.close);
          final repo = JournalRepository(db);
          final coffee = await repo.createCoffee(
            name: 'Fixture',
            roaster: 'Test',
          );
          final a = await repo.createBrew(
            coffeeId: coffee,
            methodName: method,
            doseGrams: 18,
            waterGrams: 288,
            beverageGrams: 36,
            temperatureC: 93,
            grindSetting: '5',
          );
          final b = await repo.createBrew(
            coffeeId: coffee,
            methodName: method,
            doseGrams: 18,
            waterGrams: 300,
            beverageGrams: 45,
            grindSetting: '4.5',
            timeSeconds: 30,
          );
          final brews = await db.select(db.brews).get();
          final comparison = BrewComparison(
            brews.singleWhere((r) => r.id == a),
            brews.singleWhere((r) => r.id == b),
          );
          tester.view.physicalSize = const Size(320, 1200);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            localizedApp(
              locale: Locale(language),
              theme: ThemeData(
                brightness: language == 'es'
                    ? Brightness.dark
                    : Brightness.light,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: BrewDifferencesSummary(
                    comparison: comparison,
                    repository: repo,
                    hidden: const {BrewParameter.grindSetting},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('brew-difference-grindSetting')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('brew-difference-dose')),
            findsNothing,
          );
          final temp = find.byKey(
            const ValueKey('brew-difference-temperature'),
          );
          expect(
            find.descendant(of: temp, matching: find.text('93 °C')),
            findsOneWidget,
          );
          // For espresso the temperature is the only recipe change and B
          // lacks it: the part says so once and the cell shows a dash.
          // For filter the water also changed, so the cell says it.
          final espresso = method == 'Espresso';
          expect(
            find.descendant(
              of: temp,
              matching: find.text(
                espresso
                    ? '—'
                    : language == 'es'
                    ? 'Sin dato'
                    : 'Not recorded',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('brew-difference-empty-B')),
            espresso ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('brew-difference-ratio')),
            findsOneWidget,
          );
          // A numeric change states its difference under the row.
          final water = find.byKey(const ValueKey('brew-difference-water'));
          if (water.evaluate().isNotEmpty) {
            expect(
              find.descendant(of: water, matching: find.textContaining('+12')),
              findsOneWidget,
            );
          }
          // Ratios read as everywhere else, one decimal at most (300/18 g
          // used to show 1:16.6667).
          final ratioTexts = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(const ValueKey('brew-difference-ratio')),
                  matching: find.byType(Text),
                ),
              )
              .map((t) => t.data ?? '');
          expect(
            ratioTexts.where((t) => RegExp(r'1:\d+[.,]\d{2,}').hasMatch(t)),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.text(language == 'es' ? 'Qué cambió' : 'What changed'),
          );
          await tester.pumpAndSettle();
          expect(temp, findsNothing);
          expect(await db.select(db.brews).get(), brews);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
