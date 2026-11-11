import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';
import 'package:holybeans/ui/brews/comparison_values_row.dart';
import 'package:holybeans/ui/brews/espresso_map_page.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final scenario in ['filter', 'espresso', 'espressoWithoutTds']) {
    final espresso = scenario != 'filter';
    final methodName = espresso ? 'My machine' : 'V60';
    for (final language in ['es', 'en']) {
      testWidgets(
        'compare picker, differences and compatible curves work at narrow width ($language, $scenario)',
        (tester) async {
          final db = memoryDatabase();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await db.close();
          });
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final repository = JournalRepository(db);
          final coffee = await repository.createCoffee(
            name: 'Same coffee with a long name',
            roaster: 'Test',
          );
          final method = await repository.createMethod(
            name: methodName,
            category: espresso ? 'espresso' : 'pourover',
          );
          final ids = <String>[];
          for (final water in [300.0, 320.0]) {
            ids.add(
              await repository.createBrew(
                coffeeId: coffee,
                methodName: methodName,
                methodId: method,
                doseGrams: 20,
                waterGrams: water,
                beverageGrams: espresso ? (water == 300 ? 40 : 44) : water - 40,
                timeSeconds: water.toInt(),
                tdsPercent: scenario == 'espressoWithoutTds' && water == 300
                    ? null
                    : espresso
                    ? 10
                    : water == 300
                    ? 1.2
                    : 1.4,
                notes: 'Multiline notes\nAnother line: preserved',
                brewedAt: DateTime(2026, 10, water == 300 ? 1 : 2),
              ),
            );
          }
          final curve = ShotCurve(
            timesMs: [0, 1000, 2000],
            flow: [0, 1, 2],
            weight: [0, 1, 3],
          );
          for (final id in ids) {
            await repository.saveScaleCurve(id, curve);
          }
          await tester.pumpWidget(
            HolyBeansApp(
              services: AppServices(database: db),
              initialLocale: Locale(language),
            ),
          );
          await tester.pumpAndSettle();
          await tapBottomDestination(tester, 2);
          final card = find.byKey(ValueKey('brew-card-${ids.last}'));
          await tester.tap(
            find.descendant(
              of: card,
              matching: find.byType(PopupMenuButton<String>),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('brew-compare-${ids.last}')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('compare-with-${ids.last}')),
            findsNothing,
          );
          await tester.enterText(
            find.byKey(const ValueKey('comparison-search')),
            'absent',
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('compare-with-${ids.first}')),
            findsNothing,
          );
          await tester.enterText(
            find.byKey(const ValueKey('comparison-search')),
            methodName,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('compare-with-${ids.first}')));
          await tester.pumpAndSettle();
          expect(find.byType(BrewComparisonPage), findsOneWidget);
          if (espresso) {
            final scroll = verticalScrollable(find.byType(BrewComparisonPage));
            await tester.scrollUntilVisible(
              find.byKey(
                ValueKey(
                  scenario == 'espressoWithoutTds'
                      ? 'espresso-recipe-tasting'
                      : 'espresso-map',
                ),
              ),
              250,
              scrollable: scroll,
            );
            if (scenario == 'espressoWithoutTds') {
              expect(find.byType(EspressoMapContent), findsNothing);
            } else {
              await tester.pumpAndSettle();
              final chart = tester.widget<EspressoMapChart>(
                find.byType(EspressoMapChart),
              );
              expect(chart.eyPercent, 20);
              expect(chart.tdsPercent, 10);
              expect(chart.ratio, 2);
              expect(chart.other, (
                eyPercent: 22.0,
                tdsPercent: 10.0,
                ratio: 2.2,
              ));
              expect(
                find.byKey(const ValueKey('espresso-values-a')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('espresso-values-b')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('sensory-map-chart')),
                findsNothing,
              );
              await tester.ensureVisible(
                find.byKey(const ValueKey('espresso-style-ristretto')),
              );
              await tester.tap(
                find.byKey(const ValueKey('espresso-style-ristretto')),
              );
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            expect(await db.select(db.brews).get(), hasLength(2));
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            return;
          }

          await tester.tap(
            find.text(language == 'es' ? 'Qué cambió' : 'What changed'),
          );
          await tester.pumpAndSettle();
          final scroll = verticalScrollable(find.byType(BrewComparisonPage));
          await tester.scrollUntilVisible(
            find.byWidgetPredicate(
              (w) => w is ComparisonValuesRow && w.a == '20 g' && w.b == '20 g',
            ),
            150,
            scrollable: scroll,
          );
          expect(find.text('20 g'), findsNWidgets(2));
          await tester.scrollUntilVisible(
            find.byType(ComparisonCurves),
            250,
            scrollable: scroll,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('comparison-plot-a-weight')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('comparison-series-flow')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('comparison-plot-a-flow')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('sensory-map-chart')),
            250,
            scrollable: scroll,
          );
          expect(
            find.byKey(const ValueKey('sensory-map-marker-a')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('sensory-map-marker-b')),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('comparison-curve-time')),
          );
          await tester.drag(
            find.byKey(const ValueKey('comparison-curve-time')),
            const Offset(70, 0),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The cursor reads as a time, like the rest of the app.
          expect(
            find.textContaining(RegExp(r'^\d+:\d{2} {4}A: ')),
            findsOneWidget,
          );
          expect(await db.select(db.brews).get(), hasLength(2));
          expect(await db.select(db.brewCurves).get(), hasLength(2));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'flow in ml/s and g/s is separated and missing curves remain explicit',
    (tester) async {
      final curve = ShotCurve(timesMs: [0, 1000], flow: [0, 2], weight: [0, 2]);
      Widget app(ComparisonCurve? a, ComparisonCurve? b) => localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ComparisonCurves(a: a, b: b),
          ),
        ),
      );
      await tester.pumpWidget(
        app(ComparisonCurve(curve, 'g/s'), ComparisonCurve(curve, 'ml/s')),
      );
      await tester.tap(find.byKey(const ValueKey('comparison-series-flow')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comparison-plot-a-flow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('comparison-plot-b-flow')),
        findsOneWidget,
      );
      expect(
        find.text('Flow uses different units and is shown separately.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app(ComparisonCurve(curve, 'g/s'), null));
      expect(find.text('B: This brew has no saved curve.'), findsOneWidget);
    },
  );
}
