import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_comparison_page.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkGuardAndComparison(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final coffee = await repo.createCoffee(
    name: 'Patrol comparison',
    roaster: 'Fixture',
    initialGrams: 250,
  );
  final method = await repo.createMethod(name: 'V60', category: 'pourover');
  final ids = <String>[];
  for (final water in [270.0, 288.0]) {
    final id = await repo.createBrew(
      coffeeId: coffee,
      methodName: 'V60',
      methodId: method,
      doseGrams: 18,
      waterGrams: water,
      beverageGrams: water - 35,
      timeSeconds: water.toInt(),
      tdsPercent: 1.3,
      notes: 'Keep all recorded data',
      brewedAt: DateTime(2026, 10, water == 270 ? 1 : 2),
    );
    ids.add(id);
    await repo.saveScaleCurve(
      id,
      ShotCurve(
        timesMs: [0, 1000, 2000, 3000],
        flow: [0, 2, 3, 0],
        weight: [0, 2, 5, water],
      ),
    );
  }
  final beforeBrews = await database.select(database.brews).get();
  final beforeLots = await database.select(database.coffeeLots).get();
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Add bean'));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Coffee name'),
    'Unsaved draft',
  );
  await $.tap(find.text('Cancel'));
  await $.waitUntilVisible(find.byKey(const ValueKey('keep-editing')));
  await $.takeNativeScreenshot('unsaved-coffee-confirmation');
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byType(CoffeeForm));
  expect(
    $.tester
        .widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Coffee name'),
        )
        .controller!
        .text,
    'Unsaved draft',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await $.pumpAndSettle();
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('discard-changes')));
  await $.tap(find.byKey(const ValueKey('discard-changes')));
  expect(await database.select(database.coffees).get(), hasLength(1));

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  Finder menu() => find.descendant(
    of: find.byKey(ValueKey('brew-card-${ids.last}')),
    matching: find.byType(PopupMenuButton<String>),
  );
  await $.tap(menu());
  await $.tap(find.text('Edit').last);
  final timer = find.byKey(const ValueKey('extraction-timer'));
  await $.scrollUntilVisible(
    finder: timer,
    view: verticalScrollable(find.byType(BrewForm)),
  );
  await $.tap(timer);
  await $.pump(const Duration(seconds: 2));
  await $.tap(find.text('Cancel'));
  await $.tap(find.byKey(const ValueKey('keep-editing')));
  await $.waitUntilVisible(find.text('Stop'));
  await $.takeNativeScreenshot('unsaved-brew-timer-kept');
  await $.tap(find.text('Cancel'));
  await $.tap(find.byKey(const ValueKey('discard-changes')));
  expect(await database.select(database.brews).get(), beforeBrews);
  expect(await database.select(database.coffeeLots).get(), beforeLots);
  await $.tap(menu());
  await $.tap(find.byKey(ValueKey('brew-compare-${ids.last}')));
  await $.enterText(find.byKey(const ValueKey('comparison-search')), 'Patrol');
  await $.tap(find.byKey(ValueKey('compare-with-${ids.first}')));
  await $.waitUntilVisible(find.byType(BrewComparisonPage));
  await $.takeNativeScreenshot('brew-comparison-values');
  final chart = find.byKey(const ValueKey('comparison-series-flow'));
  await $.scrollUntilVisible(
    finder: chart,
    view: verticalScrollable(find.byType(BrewComparisonPage)),
  );
  await $.tap(chart);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('comparison-curve-time')),
    view: verticalScrollable(find.byType(BrewComparisonPage)),
  );
  await $.tester.drag(
    find.byKey(const ValueKey('comparison-curve-time')),
    const Offset(100, 0),
  );
  await $.pumpAndSettle();
  await $.takeNativeScreenshot('brew-comparison-curves');
  expect(find.byKey(const ValueKey('comparison-plot-a-flow')), findsOneWidget);
  await $.platformAutomator.android.pressBack();
  expect(await database.select(database.brews).get(), beforeBrews);
  expect(await database.select(database.coffeeLots).get(), beforeLots);
  expect(await database.select(database.brewCurves).get(), hasLength(2));
}
