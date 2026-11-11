import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

/// Hides a parameter from Settings → Brew parameters and checks that the
/// brew details hide it, count it and reveal it, while the value is kept.
Future<void> checkBrewParameters(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Parameter bean',
    roaster: 'Test',
  );
  final method = await repository.createMethod(
    name: 'Espresso test',
    category: 'espresso',
  );
  await repository.createBrew(
    coffeeId: coffee,
    methodName: 'Espresso test',
    methodId: method,
    doseGrams: 18,
    beverageGrams: 40,
    timeSeconds: 30,
    firstDripSeconds: 5,
    notes: 'Kept while hidden',
  );
  await BrewParameterSettings(database).saveShared({BrewParameter.dose});
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );

  await $.tap(find.byTooltip('Settings'));
  await $.tap(find.byKey(const ValueKey('brew-parameters')));
  await $.waitUntilVisible(find.text('Brew parameters'));
  await $.takeNativeScreenshot('brew-parameters');
  final dose = find.byKey(const ValueKey('parameter-share-dose'));
  await $.scrollUntilVisible(finder: dose, view: find.byType(Scrollable).last);
  expect(
    find.byKey(const ValueKey('parameter-last-shared-hint')),
    findsOneWidget,
  );
  final coffeeShare = find.byKey(const ValueKey('parameter-share-coffee'));
  await $.scrollUntilVisible(
    finder: coffeeShare,
    view: find.byType(Scrollable).last,
    scrollDirection: AxisDirection.up,
  );
  await $.tap(coffeeShare);
  expect(
    find.byKey(const ValueKey('parameter-last-shared-hint')),
    findsNothing,
  );
  final notes = find.byKey(const ValueKey('parameter-show-notes'));
  await $.scrollUntilVisible(finder: notes, view: find.byType(Scrollable).last);
  await $.tap(notes);
  expect(await BrewParameterSettings(database).loadHidden(), {
    BrewParameter.notes,
  });
  await $.tester.pageBack();
  await $.pumpAndSettle();
  await $.tester.pageBack();
  await $.pumpAndSettle();

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.tap(find.text('Parameter bean').first);
  await $.waitUntilVisible(find.text('1 hidden value, Show'));
  expect(find.text('Kept while hidden'), findsNothing);
  expect(find.text('First drip'), findsOneWidget);
  await $.takeNativeScreenshot('brew-details-hidden');
  await $.tap(find.byKey(const ValueKey('brew-detail-hidden')));
  await $.waitUntilVisible(find.text('Kept while hidden'));
  final brew = await database.select(database.brews).getSingle();
  expect(brew.notes, 'Kept while hidden');

  // An espresso with TDS opens the espresso map, not the sensory one.
  // The details are a bottom sheet: the system back closes them.
  await $.platform.android.pressBack();
  await $.pumpAndSettle();
  final espresso = await repository.createBrew(
    coffeeId: coffee,
    methodName: 'Espresso test',
    methodId: method,
    doseGrams: 16,
    beverageGrams: 36.3,
    timeSeconds: 28,
    tdsPercent: 8.66,
  );
  await $.pumpAndSettle();
  final card = find.byKey(ValueKey('brew-card-$espresso'));
  await $.scrollUntilVisible(finder: card);
  await $.tap(card);
  final open = find.byKey(const ValueKey('open-espresso-map-button'));
  await $.scrollUntilVisible(finder: open, view: find.byType(Scrollable).last);
  await $.tap(open);
  await $.waitUntilVisible(find.text('Within Normale'));
  await $.takeNativeScreenshot('espresso-map');
  await $.tap(find.byKey(const ValueKey('espresso-style-ristretto')));
  await $.waitUntilVisible(find.text('Extraction in range, Low TDS'));
  await $.takeNativeScreenshot('espresso-map-ristretto');
  await $.tester.pageBack();
  await $.pumpAndSettle();
}
