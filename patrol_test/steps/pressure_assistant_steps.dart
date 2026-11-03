import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_page.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/fake_pressure_sensor.dart';

Future<void> checkPressureAssistant(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Lever reference',
    roaster: 'Patrol',
  );
  final method = await repo.createMethod(name: 'Lever', category: 'espresso');
  final brew = await repo.createBrew(
    coffeeId: coffee,
    methodId: method,
    methodName: 'Lever',
    doseGrams: 18,
  );
  final curve = ShotCurve(
    timesMs: [0, 3000, 6000, 10000, 20000],
    pressure: [0, 2, 9, 9, 5],
    flow: [],
    weight: [0, 0, 3, 12, 36],
  );
  await repo.saveScaleCurve(brew, curve);
  final coffees = await repo.allCoffees();
  final sensor = FakePressureSensor(name: 'BOOKOO test', connected: true);
  await $.pumpWidgetAndSettle(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BrewForm(
          repository: repo,
          settings: BrewParameterSettings(db),
          coffees: coffees,
          initialCoffeeId: coffee,
          initialMethodId: method,
          pressureSensor: sensor,
        ),
      ),
    ),
  );
  final entry = find.byKey(const ValueKey('pressure-assistant'));
  await $.scrollUntilVisible(
    finder: entry,
    view: find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await $.tap(entry);
  await $.enterText(find.byType(TextField), 'not present');
  expect(
    find.textContaining('No shots with a usable pressure'),
    findsOneWidget,
  );
  await $.enterText(find.byType(TextField), 'Lever');
  await $.tap(find.byKey(ValueKey('pressure-reference-$brew')));
  expect(find.byType(PressureGuidePage), findsOneWidget);
  await $.takeNativeScreenshot('pressure-guide-ready');
  await $.tap(find.byKey(const ValueKey('pressure-guide-toggle')));
  for (final pressure in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]) {
    sensor.emit(pressure);
    await $.pump(const Duration(milliseconds: 500));
  }
  final live = $.tester.widget<PressureGuideChart>(
    find.byType(PressureGuideChart),
  );
  expect(live.trace.length, greaterThanOrEqualTo(8));
  expect(live.trace.last.bar, 7);
  expect(find.byKey(const ValueKey('pressure-actual')), findsOneWidget);
  expect(find.text('Stop'), findsOneWidget);
  await $.takeNativeScreenshot('pressure-guide-live-overlay');
  await $.tap(find.byKey(const ValueKey('pressure-guide-toggle')));
  await $.takeNativeScreenshot('pressure-guide-live-stopped');
  await $.tap(find.byType(BackButton));
  await $.tap(find.byType(BackButton));
  expect(find.byType(BrewForm), findsOneWidget);
  expect((await repo.allBrews()).length, 1);
  expect((await repo.brewCurve(brew))!.curve.toJson(), curve.toJson());
  await $.pumpWidgetAndSettle(const SizedBox.shrink());
  sensor.dispose();
}
