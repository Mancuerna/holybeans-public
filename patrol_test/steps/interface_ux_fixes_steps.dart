import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/equipment/equipment_page.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkInterfaceUxForm(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffeeId = await repository.createCoffee(
    name: 'Interface form coffee',
    roaster: 'Patrol',
    initialGrams: 500,
  );
  final espressoId = await repository.createMethod(
    name: 'Lever',
    category: 'espresso',
  );
  final filterId = await repository.createMethod(
    name: 'V60',
    category: 'pourover',
  );
  await repository.createBrew(
    coffeeId: coffeeId,
    methodId: filterId,
    methodName: 'V60',
    doseGrams: 18,
    waterGrams: 396,
    timeSeconds: 170,
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await $.tap(find.text('Brew'));
  await $.waitUntilVisible(find.byType(BrewForm));
  final form = verticalScrollable(find.byType(BrewForm));
  final singleLot = find.byKey(const ValueKey('brew-single-lot'));
  expect(singleLot, findsOneWidget);
  expect(
    find.descendant(of: singleLot, matching: find.text('Inventory 1, 500 g')),
    findsOneWidget,
  );

  Future<void> chooseMethod(
    String name, {
    AxisDirection direction = AxisDirection.down,
  }) async {
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Choose a method',
    );
    await $.scrollUntilVisible(
      finder: field,
      view: form,
      scrollDirection: direction,
    );
    await $.tap(field);
    await $.tap(find.text(name).last);
    await $.pumpAndSettle();
  }

  await chooseMethod('Lever');
  final dose = find.widgetWithText(TextFormField, 'Dose (g)');
  await $.scrollUntilVisible(finder: dose, view: form);
  await $.enterText(dose, '0');
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.text('Enter a valid number'));
  expect(
    $.tester
        .widget<EditableText>(
          find.descendant(of: dose, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus,
    isTrue,
  );
  expect(await repository.allBrews(), hasLength(1));
  await $.takeNativeScreenshot('interface-ux-save-revealed');

  final timer = find.byKey(const ValueKey('extraction-timer'));
  await $.scrollUntilVisible(finder: timer, view: form);
  final seconds = find.widgetWithText(TextFormField, 'Seconds');
  await $.scrollUntilVisible(finder: seconds, view: form);
  await $.enterText(seconds, '75');
  await $.scrollUntilVisible(finder: timer, view: form);
  await $.tap(timer);
  await $.pump(const Duration(seconds: 2));
  expect($.tester.widget<TextFormField>(seconds).controller!.text, '75');
  expect(
    find.text('Enter whole minutes and seconds from 0 to 59.'),
    findsOneWidget,
  );
  expect(find.text('Start'), findsOneWidget);
  expect(await repository.allBrews(), hasLength(1));
  await $.scrollUntilVisible(finder: seconds, view: form);
  await $.enterText(seconds, '30');
  await $.scrollUntilVisible(
    finder: dose,
    view: form,
    scrollDirection: AxisDirection.up,
  );
  await $.enterText(dose, '18');
  await chooseMethod('V60', direction: AxisDirection.up);

  final slider = find.byKey(const ValueKey('brew-ratio-slider'));
  await $.scrollUntilVisible(finder: slider, view: form);
  expect($.tester.widget<Slider>(slider).value, 20);
  expect($.tester.widget<Slider>(slider).onChanged, isNull);
  await $.tap(find.byKey(const ValueKey('brew-ratio-decrease')));
  expect($.tester.widget<Slider>(slider).value, 20);
  await $.tap(find.byKey(const ValueKey('brew-ratio-increase')));
  expect($.tester.widget<Slider>(slider).value, 20);
  final water = find.widgetWithText(TextFormField, 'Water (g)');
  expect($.tester.widget<TextFormField>(water).controller!.text, '396');
  await $.scrollUntilVisible(
    finder: water,
    view: form,
    scrollDirection: AxisDirection.up,
  );
  await $.enterText(water, '2599');
  await $.scrollUntilVisible(finder: slider, view: form);
  expect($.tester.widget<Slider>(slider).value, 20);
  expect($.tester.widget<Slider>(slider).onChanged, isNull);
  await $.tap(find.byKey(const ValueKey('brew-ratio-decrease')));
  expect($.tester.widget<TextFormField>(water).controller!.text, '2592');
  await $.scrollUntilVisible(
    finder: water,
    view: form,
    scrollDirection: AxisDirection.up,
  );
  await $.enterText(water, '396');
  expect($.tester.widget<TextFormField>(water).controller!.text, '396');
  await $.takeNativeScreenshot('interface-ux-ratio-custom');
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.text('Brew saved'));
  final saved = (await repository.allBrews()).singleWhere(
    (brew) => brew.methodId == filterId && brew.timeSeconds == 30,
  );
  expect((saved.doseGrams, saved.waterGrams), (18, 396));
  expect(saved.methodId, isNot(espressoId));
}

Future<void> checkInterfaceUxHistory(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffeeId = await repository.createCoffee(
    name: 'Method history coffee',
    roaster: 'Patrol',
  );
  await repository.createCoffee(name: 'Other coffee', roaster: 'Other');
  final methodId = await repository.createMethod(
    name: 'Old espresso name',
    category: 'espresso',
  );
  final brewId = await repository.createBrew(
    coffeeId: coffeeId,
    methodId: methodId,
    methodName: 'Old espresso name',
    doseGrams: 18,
    beverageGrams: 36,
  );
  await repository.createBrew(
    coffeeId: coffeeId,
    methodName: 'V60',
    doseGrams: 18,
    waterGrams: 396,
  );
  await repository.updateMethod(id: methodId, name: 'Renamed lever');
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );

  Future<void> tab(String name) => $.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(name)),
  );

  await tab('Brews');
  await $.enterText(find.byType(TextField).first, 'no matching brew');
  await $.tap(find.byKey(const ValueKey('history-filter-button')));
  await $.tap(find.byKey(const ValueKey('history-period-week')));
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  expect(find.byType(Card), findsNothing);

  await tab('Equipment');
  final methodBrews = find.byKey(ValueKey('method-brews-$methodId'));
  await $.scrollUntilVisible(
    finder: methodBrews,
    view: verticalScrollable(find.byType(EquipmentPage)),
  );
  await $.tap(methodBrews);
  await $.waitUntilVisible(find.byKey(ValueKey('brew-card-$brewId')));
  expect(
    $.tester.widget<TextField>(find.byType(TextField).first).controller!.text,
    isEmpty,
  );
  expect(find.byKey(const ValueKey('history-active-date')), findsNothing);
  expect(find.text('Renamed lever'), findsWidgets);
  expect(find.textContaining('Old espresso name'), findsWidgets);
  await $.takeNativeScreenshot('interface-ux-renamed-method');

  await $.tap(find.byTooltip('Clear filter: Renamed lever'));
  await $.pumpAndSettle();
  expect(find.byType(Card), findsNWidgets(2));
  expect(await repository.allBrews(), hasLength(2));
}
