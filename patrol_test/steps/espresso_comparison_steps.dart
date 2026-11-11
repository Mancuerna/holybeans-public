import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/brews/comparison_plot.dart';
import 'package:holybeans/ui/brews/espresso_combined_plot.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkEspressoComparison(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Patrol espresso comparison',
    roaster: 'Fixture',
    initialGrams: 250,
  );
  final method = await repo.createMethod(
    name: 'Espresso',
    category: 'espresso',
  );
  final ids = <String>[];
  for (final duration in [32, 28]) {
    final id = await repo.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'Espresso',
      doseGrams: 18,
      beverageGrams: 36,
      temperatureC: duration == 32 ? 93 : 91,
      grindSetting: duration == 32 ? '5' : '4.5',
      timeSeconds: duration,
      firstDripSeconds: duration == 32 ? 7 : 5,
      pressureBar: 8,
      tdsPercent: 9,
      rating: 8,
      notes: 'Saved tasting notes',
      brewedAt: DateTime(2026, 10, duration == 32 ? 1 : 2),
    );
    ids.add(id);
    await repo.saveScaleCurve(
      id,
      ShotCurve(
        timesMs: [0, 5000, 7000, 15000, duration * 1000],
        pressure: [0, 4, 9, 8, 0],
        flow: [0, 0, 1, 2, 0],
        weight: [0, 0, 2, 18, 36],
      ),
    );
  }
  final brews = await db.select(db.brews).get();
  final lots = await db.select(db.coffeeLots).get();
  final curves = await db.select(db.brewCurves).get();
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: db),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byKey(ValueKey('brew-card-${ids.last}')),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await $.tap(find.byKey(ValueKey('brew-compare-${ids.last}')));
  await $.tap(find.byKey(ValueKey('compare-with-${ids.first}')));
  await $.waitUntilVisible(find.text('Compare shots'));
  expect(
    find.byKey(const ValueKey('brew-difference-temperature')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('brew-difference-grindSetting')),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('espresso-comparison-changes');
  await $.tap(find.text('What changed'));
  await $.takeNativeScreenshot('espresso-comparison-overview');
  final page = verticalScrollable(find.byType(BrewComparisonPage));
  final chart = find.byKey(const ValueKey('espresso-combined-plot'));
  await $.scrollUntilVisible(finder: chart, view: page);
  await $.tester.drag(chart, const Offset(80, 0));
  await $.pumpAndSettle();
  expect($.tester.widget<EspressoCombinedPlot>(chart).cursorMs, greaterThan(0));
  expect(
    find.byKey(const ValueKey('espresso-combined-value-a')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('espresso-combined-value-b')),
    findsOneWidget,
  );
  await $.scrollUntilVisible(
    finder: find.text('First drip').first,
    view: page,
    delta: -300,
  );
  await $.tap(find.text('First drip').first);
  final aligned = $.tester.widget<EspressoCombinedPlot>(chart);
  expect(aligned.timeline.minMs, -7000);
  expect(aligned.cursorMs, 0);
  await $.takeNativeScreenshot('espresso-comparison-first-drip');
  final play = find.byKey(const ValueKey('comparison-playback'));
  await $.scrollUntilVisible(finder: play, view: page);
  await $.tester.tap(play);
  await $.tester.pump();
  await $.tester.pump(const Duration(milliseconds: 800));
  expect($.tester.widget<EspressoCombinedPlot>(chart).cursorMs, greaterThan(0));
  expect(find.byTooltip('Pause comparison'), findsOneWidget);
  await $.tester.tap(play);
  await $.pumpAndSettle();
  final paused = $.tester.widget<EspressoCombinedPlot>(chart).cursorMs;
  await $.tester.pump(const Duration(milliseconds: 400));
  expect($.tester.widget<EspressoCombinedPlot>(chart).cursorMs, paused);
  await $.takeNativeScreenshot('espresso-comparison-playback');

  final separated = find.byKey(const ValueKey('espresso-separated-mode'));
  await $.scrollUntilVisible(finder: separated, view: page, delta: -300);
  await $.tap(separated);
  final pressure = find.byKey(const ValueKey('espresso-plot-both-pressure'));
  await $.scrollUntilVisible(finder: pressure, view: page);
  expect(find.byType(ComparisonPlot), findsNWidgets(2));
  await $.takeNativeScreenshot('espresso-comparison-panels');
  final weight = find.byKey(const ValueKey('espresso-weight-toggle'));
  await $.scrollUntilVisible(finder: weight, view: page);
  await $.tap(
    find.descendant(of: weight, matching: find.byType(ListTile)).first,
  );
  final slider = find.byKey(const ValueKey('espresso-comparison-time'));
  await $.scrollUntilVisible(finder: slider, view: page);
  await $.tester.drag(slider, const Offset(50, 0));
  await $.pumpAndSettle();
  expect(
    $.tester
        .widgetList<ComparisonPlot>(find.byType(ComparisonPlot))
        .map((p) => p.cursorMs)
        .toSet(),
    hasLength(1),
  );
  await $.takeNativeScreenshot('espresso-comparison-output');
  final details = find.byKey(const ValueKey('espresso-recipe-tasting'));
  await $.scrollUntilVisible(finder: details, view: page);
  await $.takeNativeScreenshot('espresso-comparison-results');
  await $.tap(
    find.descendant(of: details, matching: find.byType(ListTile)).first,
  );
  await $.scrollUntilVisible(
    finder: find.text('Saved tasting notes').first,
    view: page,
  );
  await $.takeNativeScreenshot('espresso-comparison-recipe-tasting');
  await $.platformAutomator.android.pressBack();
  expect(await db.select(db.brews).get(), brews);
  expect(await db.select(db.coffeeLots).get(), lots);
  expect(await db.select(db.brewCurves).get(), curves);
}
