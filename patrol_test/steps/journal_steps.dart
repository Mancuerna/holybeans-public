import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// The history keeps both brews in separate cards.
Future<void> checkHistory(PatrolIntegrationTester $) async {
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.waitUntilVisible(find.text('Patrol Kenya').first);
  final historyList = pageListContaining(find.text('Patrol Kenya').first);
  expect(
    find.descendant(of: historyList, matching: find.text('Patrol Kenya')),
    findsNWidgets(2),
  );
  expectCardsSeparated(
    $.tester,
    historyList,
    find.ancestor(of: find.text('Patrol Kenya'), matching: find.byType(Card)),
    expectedCount: 2,
  );
  await $.tap(find.text('Patrol Kenya').first);
  await $.waitUntilVisible(find.text('Pre-ground'));
  expect(find.text('22 clicks'), findsNothing);
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
  await $.takeNativeScreenshot('history-two-brews');
}

/// Adds «Patrol Colombia» with a suggested origin, then freezes part of
/// it and thaws a dose.
Future<void> addSecondBeanAndFreeze(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Add bean'));
  final secondBeanName = find.widgetWithText(TextFormField, 'Coffee name');
  await $.tap(secondBeanName);
  await $.enterText(secondBeanName, 'Patrol Colombia');
  final secondFormScrollable = verticalScrollable(find.byType(CoffeeForm));
  final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
  await $.scrollUntilVisible(finder: addOrigin, view: secondFormScrollable);
  await $.tap(addOrigin);
  final countryField = find.byKey(const ValueKey('origin-country'));
  await $.scrollUntilVisible(finder: countryField, view: secondFormScrollable);
  // Patrol's enterText drops focus, which closes the suggestions.
  await $.tap(countryField);
  await $.tester.enterText(countryField, 'Colom');
  await $.tester.pumpAndSettle();
  await $.tap(find.byKey(const ValueKey('country-option-CO')));
  await $.waitUntilVisible(find.text('🇨🇴  '));
  await $.takeNativeScreenshot('country-suggestion-flag');
  final secondQuantity = find.widgetWithText(
    TextFormField,
    'Purchased quantity (g)',
  );
  await $.scrollUntilVisible(
    finder: secondQuantity,
    view: secondFormScrollable,
  );
  await $.enterText(secondQuantity, '250');
  await $.tap(find.text('Save'));

  await $.waitUntilVisible(find.text('Patrol Colombia'));
  await $.waitUntilVisible(find.text('Patrol Kenya'));
  final coffees = await database.select(database.coffees).get();
  expect(coffees, hasLength(2));
  expect(
    coffees.map((coffee) => coffee.name),
    containsAll(['Patrol Kenya', 'Patrol Colombia']),
  );
  final beansList = pageListContaining(find.text('Patrol Colombia'));
  final colombia = coffees.singleWhere(
    (coffee) => coffee.name == 'Patrol Colombia',
  );
  final colombiaComponents = await database
      .select(database.coffeeComponents)
      .get();
  expect(colombiaComponents.single.country, 'Colombia');
  expect(
    $.tester
        .widget<Text>(find.byKey(ValueKey('bean-origin-${colombia.id}')))
        .textSpan!
        .toPlainText(includeSemanticsLabels: false),
    '🇨🇴  Colombia',
  );
  expect(
    find.descendant(of: beansList, matching: find.text('Patrol Kenya')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: beansList, matching: find.text('Patrol Colombia')),
    findsOneWidget,
  );
  expectCardsSeparated(
    $.tester,
    beansList,
    find.byWidgetPredicate(
      (widget) =>
          widget is Card &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('bean-card-'),
    ),
    expectedCount: 2,
  );
  await $.takeNativeScreenshot('beans-two-coffees');

  // Freeze part of the new bag, then thaw a dose.
  await $.tap(find.text('Patrol Colombia'));
  final colombiaSheet = verticalScrollable(find.byType(BottomSheet));
  final freezeButton = find.byKey(const ValueKey('freeze-coffee-button'));
  await $.scrollUntilVisible(finder: freezeButton, view: colombiaSheet);
  await $.tap(freezeButton);
  await $.enterText(find.byKey(const ValueKey('freeze-grams')), '100');
  final freezeSave = find.byKey(const ValueKey('freeze-save'));
  await $.scrollUntilVisible(
    finder: freezeSave,
    view: verticalScrollable(find.byType(BottomSheet).last),
  );
  await $.tap(freezeSave);
  await $.tester.pumpAndSettle();
  final portion = await database.select(database.frozenPortions).getSingle();
  expect(portion.remainingGrams, 100);
  final thawButton = find.byKey(ValueKey('thaw-${portion.id}'));
  await $.scrollUntilVisible(finder: thawButton, view: colombiaSheet);
  await $.tap(thawButton);
  await $.enterText(find.byKey(const ValueKey('thaw-grams')), '18');
  await $.tap(find.byKey(const ValueKey('thaw-confirm')));
  await $.tester.pumpAndSettle();
  expect(
    (await database.select(database.frozenPortions).getSingle()).remainingGrams,
    82,
  );
  final colombiaLot = (await database.select(database.coffeeLots).get())
      .singleWhere((lot) => lot.coffeeId == colombia.id);
  expect(colombiaLot.remainingGrams, 168);
  await $.scrollUntilVisible(
    finder: find.byKey(ValueKey('frozen-portion-${portion.id}')),
    view: colombiaSheet,
  );
  await $.takeNativeScreenshot('bean-freezer');
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
  await $.tap(find.text('Frozen (1)'));
  await $.waitUntilVisible(find.text('Patrol Colombia'));
  await $.tap(find.text('Available (2)'));
}

/// Archives V60, shows and restores it, and opens the grinders.
Future<void> archiveAndRestoreMethod(PatrolIntegrationTester $) async {
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Equipment'),
    ),
  );
  await $.waitUntilVisible(find.text('V60'));
  await $.tap(find.byTooltip('Actions').first);
  await $.tap(find.text('Archive method'));
  await $.tester.pumpAndSettle();
  expect(find.text('V60'), findsNothing);
  await $.tap(find.byKey(const ValueKey('equipment-show-archived')));
  await $.waitUntilVisible(find.text('V60'));
  await $.tap(find.byTooltip('Actions').first);
  await $.tap(find.text('Restore method'));
  await $.tap(find.byKey(const ValueKey('equipment-show-archived')));
  await $.waitUntilVisible(find.text('V60'));
  await $.tap(
    find.descendant(
      of: find.byKey(const ValueKey('equipment-tabs')),
      matching: find.text('Grinders'),
    ),
  );
  await $.waitUntilVisible(find.text('Patrol grinder'));
}

/// Edits the first bean's remaining weight, keeping purchase and price.
Future<void> editFirstBean(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  var coffees = await database.select(database.coffees).get();
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  final kenyaBeforeEdit = coffees.singleWhere(
    (coffee) => coffee.name == 'Patrol Kenya',
  );
  final originalRoastDate = (await database.select(database.coffeeLots).get())
      .singleWhere((lot) => lot.coffeeId == kenyaBeforeEdit.id)
      .roastDate;
  await $.tap(find.text('Patrol Kenya'));
  await $.tap(find.byTooltip('Edit bean'));
  final editScrollable = find
      .descendant(
        of: find.byType(CoffeeForm),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final editRoastDate = find.widgetWithText(TextFormField, 'Roast date');
  await $.scrollUntilVisible(finder: editRoastDate, view: editScrollable);
  final roastDateText = $.tester
      .widget<TextFormField>(editRoastDate)
      .controller!
      .text;
  expect(roastDateText, isNotEmpty);
  final editQuantity = find.widgetWithText(
    TextFormField,
    'Purchased quantity (g)',
  );
  await $.scrollUntilVisible(finder: editQuantity, view: editScrollable);
  expect($.tester.widget<TextFormField>(editQuantity).controller!.text, '250');
  final remainingQuantity = find.widgetWithText(
    TextFormField,
    'Remaining quantity (g)',
  );
  await $.scrollUntilVisible(finder: remainingQuantity, view: editScrollable);
  expect(
    $.tester.widget<TextFormField>(remainingQuantity).controller!.text,
    '214',
  );
  await $.enterText(remainingQuantity, '430');
  await $.takeNativeScreenshot('bean-edit-remaining-quantity');
  final editPrice = find.widgetWithText(TextFormField, 'Paid price (€)');
  await $.scrollUntilVisible(finder: editPrice, view: editScrollable);
  expect($.tester.widget<TextFormField>(editPrice).controller!.text, '12.50');
  final editedPricePerKg = find.widgetWithText(ListTile, formatEuro(50));
  await $.scrollUntilVisible(finder: editedPricePerKg, view: editScrollable);
  expect(editedPricePerKg, findsOneWidget);
  await $.tap(find.text('Save'));

  coffees = await database.select(database.coffees).get();
  var lots = await database.select(database.coffeeLots).get();
  final kenyaCoffee = coffees.singleWhere(
    (coffee) => coffee.name == 'Patrol Kenya',
  );
  final kenyaLot = lots.singleWhere((lot) => lot.coffeeId == kenyaCoffee.id);
  expect(kenyaCoffee.paidPriceCents, 1250);
  expect(kenyaLot.roastDate, originalRoastDate);
  expect(kenyaLot.initialGrams, 250);
  expect(kenyaLot.remainingGrams, 430);

  await $.tap(find.text('Patrol Kenya'));
  await $.waitUntilVisible(find.text('${formatEuro(50)}/kg'));
  await $.waitUntilVisible(find.text('430 g'));
  await $.takeNativeScreenshot('bean-remaining-quantity-updated');

  lots = await database.select(database.coffeeLots).get();
  final updatedKenyaLot = lots.singleWhere(
    (lot) => lot.coffeeId == kenyaCoffee.id,
  );
  expect(updatedKenyaLot.initialGrams, 250);
  expect(updatedKenyaLot.remainingGrams, 430);
}

/// A brew beyond the stock offers to archive the bean with its average.
Future<void> overdrawAndArchive(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final kenyaCoffee = (await database.select(database.coffees).get())
      .singleWhere((coffee) => coffee.name == 'Patrol Kenya');
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Home'),
    ),
  );
  await $.waitUntilVisible(find.text('frozen today'));
  await $.tap(find.text('Brew').last);
  final overdraftScrollable = find
      .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
      .first;
  final overdraftDose = find.widgetWithText(TextFormField, 'Dose (g)');
  await $.scrollUntilVisible(finder: overdraftDose, view: overdraftScrollable);
  await $.enterText(overdraftDose, '500');
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.byKey(const ValueKey('coffee-archive-dialog')));
  expect(
    $.tester
        .widget<Text>(find.byKey(const ValueKey('archive-average-rating')))
        .data,
    'Your brews average 7.5 (1)',
  );
  await $.takeNativeScreenshot('overdraw-archive-rating-dialog');
  await $.tap(find.byKey(const ValueKey('archive-use-average')));
  await $.waitUntilVisible(find.text('Rating: 7.5 / 10'));
  await $.tap(find.text('Archive bean').last);
  await $.tester.pumpAndSettle();

  final coffees = await database.select(database.coffees).get();
  final brews = await database.select(database.brews).get();
  final lots = await database.select(database.coffeeLots).get();
  final archivedKenya = coffees.singleWhere(
    (coffee) => coffee.id == kenyaCoffee.id,
  );
  final overdrawnKenyaLot = lots.singleWhere(
    (lot) => lot.coffeeId == kenyaCoffee.id,
  );
  expect(archivedKenya.archivedAtMs, isNotNull);
  expect(archivedKenya.rating, 7.5);
  expect(brews, hasLength(3));
  expect(
    brews
        .where((brew) => brew.coffeeId == kenyaCoffee.id)
        .every(
          (brew) => brew.archivedByCoffee == true && brew.archivedAtMs != null,
        ),
    isTrue,
  );
  expect(overdrawnKenyaLot.remainingGrams, 0);
  expect(overdrawnKenyaLot.overdrawGrams, 70);

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.text('Archived (1)'));
  await $.tap(find.text('Patrol Kenya'));
  await $.waitUntilVisible(find.text('7.5 / 10'));
  await $.waitUntilVisible(find.text('0 g'));
  await $.takeNativeScreenshot('archived-coffee-rating');
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
}

/// Stats show activity in the overview, then the top method and the sour
/// brew on the map in the brews tab, and the costs tab.
Future<void> checkStats(PatrolIntegrationTester $) async {
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Home'),
    ),
  );
  await $.tap(find.byTooltip('Stats'));
  await $.waitUntilVisible(find.byKey(const ValueKey('stats-overview')));
  await $.takeNativeScreenshot('stats-overview');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('stats-activity')),
    view: verticalScrollable(find.byKey(const ValueKey('stats-list'))),
  );

  Future<void> openTab(String name) => $.tap(
    find.descendant(
      of: find.byKey(const ValueKey('stats-tabs')),
      matching: find.text(name),
    ),
  );
  await openTab('Brews');
  final brewsList = verticalScrollable(
    find.byKey(const ValueKey('stats-list-brews')),
  );
  // The row's centre is the gap between name and count, which is not
  // hit-testable, so aim at the name.
  final topMethod = find.descendant(
    of: find.byKey(const ValueKey('stats-methods-0')),
    matching: find.text('V60'),
  );
  await $.scrollUntilVisible(finder: topMethod, view: brewsList);
  final sourMapCell = find.byKey(const ValueKey('stats-compass--1-0'));
  await $.scrollUntilVisible(finder: sourMapCell, view: brewsList);
  expect(
    find.descendant(of: sourMapCell, matching: find.text('1')),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('stats-extraction-methods');

  await openTab('Costs');
  await $.waitUntilVisible(find.byKey(const ValueKey('stats-list-costs')));
  await $.takeNativeScreenshot('stats-costs');
}
