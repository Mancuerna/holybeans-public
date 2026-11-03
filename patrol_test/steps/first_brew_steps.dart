import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/sensory_map_page.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// Adds «Patrol Kenya» with the keyboard open over the name field.
Future<void> addFirstBean(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.tap(find.text('Add bean'));
  final nameField = find.widgetWithText(TextFormField, 'Coffee name');
  await $.tap(nameField);
  await waitForKeyboard($.tester);

  final title = find.descendant(
    of: find.byType(CoffeeForm),
    matching: find.text('Add bean'),
  );
  final titleBounds = $.tester.getRect(title);
  final nameFieldBounds = $.tester.getRect(nameField);
  final nameLabelBounds = $.tester.getRect(find.text('Coffee name'));
  expect($.tester.view.viewInsets.bottom, greaterThan(0));
  expect(nameFieldBounds.top, greaterThan(titleBounds.bottom));
  expect(nameLabelBounds.top, greaterThan(titleBounds.bottom));
  await $.takeNativeScreenshot('coffee-name-keyboard');

  await $.enterText(nameField, 'Patrol Kenya');
  await $.enterText(
    find.widgetWithText(TextFormField, 'Roaster'),
    'HolyBeans smoke test',
  );
  final formScrollable = find
      .descendant(
        of: find.byType(CoffeeForm),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final roastDate = find.widgetWithText(TextFormField, 'Roast date');
  await $.scrollUntilVisible(finder: roastDate, view: formScrollable);
  await $.tap(roastDate);
  await $.tap(find.text('OK').last);

  final purchasedQuantity = find.widgetWithText(
    TextFormField,
    'Purchased quantity (g)',
  );
  await $.scrollUntilVisible(finder: purchasedQuantity, view: formScrollable);
  await $.enterText(purchasedQuantity, '250');
  final paidPrice = find.widgetWithText(TextFormField, 'Paid price (€)');
  await $.scrollUntilVisible(finder: paidPrice, view: formScrollable);
  await $.enterText(paidPrice, '12.50');
  final createdPricePerKg = find.text(formatEuro(50));
  await $.scrollUntilVisible(finder: createdPricePerKg, view: formScrollable);
  expect(createdPricePerKg, findsOneWidget);
  await $.tap(find.text('Save'));

  final coffees = await database.select(database.coffees).get();
  expect(coffees, hasLength(1));
  expect(coffees.single.name, 'Patrol Kenya');
  final lots = await database.select(database.coffeeLots).get();
  expect(lots, hasLength(1));
  expect(lots.single.remainingGrams, 250);
}

/// Brews it with a new V60, tool and grinder, and checks the stock.
Future<void> brewFirstCup(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.tap(find.text('Brew'));
  await $.tester.pumpAndSettle();
  expect(find.text('Inventory lot'), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await $.tap(find.text('Add method'));
  await $.enterText(find.widgetWithText(TextFormField, 'Method name'), 'V60');
  await $.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Style',
    ),
  );
  await $.tap(find.text('Pour-over').last);
  await $.tap(find.text('Save').last);
  await $.tester.pumpAndSettle();

  final brewScrollable = find
      .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
      .first;
  final manageTools = find.widgetWithText(TextButton, 'Manage accessories');
  await $.scrollUntilVisible(finder: manageTools, view: brewScrollable);
  await $.tap(manageTools);
  await $.tap(find.byTooltip('Add accessory'));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Accessory name'),
    'Filter paper',
  );
  await $.tap(find.text('Save').last);
  await $.tester.pumpAndSettle();
  await $.tap(find.byTooltip('Cancel'));
  await $.tester.pumpAndSettle();
  final firstToolChip = find.widgetWithText(FilterChip, 'Filter paper');
  await $.scrollUntilVisible(finder: firstToolChip, view: brewScrollable);
  await $.tap(firstToolChip);

  await $.scrollUntilVisible(
    finder: find.byTooltip('Add grinder'),
    view: brewScrollable,
  );
  await $.tap(find.byTooltip('Add grinder'));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Grinder name'),
    'Patrol grinder',
  );
  await $.tap(find.text('Save').last);
  await $.tester.pumpAndSettle();
  await $.scrollUntilVisible(
    finder: find.widgetWithText(TextFormField, 'Grind setting'),
    view: brewScrollable,
  );
  await $.enterText(
    find.widgetWithText(TextFormField, 'Grind setting'),
    '22 clicks',
  );
  await $.scrollUntilVisible(
    finder: find.widgetWithText(TextFormField, 'Dose (g)'),
    view: brewScrollable,
  );
  await $.enterText(find.widgetWithText(TextFormField, 'Dose (g)'), '18');
  final brewWater = find.widgetWithText(TextFormField, 'Water (g)');
  await $.scrollUntilVisible(finder: brewWater, view: brewScrollable);
  await $.enterText(brewWater, '275');
  final durationMinutes = find.widgetWithText(TextFormField, 'Minutes');
  await $.scrollUntilVisible(finder: durationMinutes, view: brewScrollable);
  final timerButton = find.byKey(const ValueKey('extraction-timer'));
  await $.scrollUntilVisible(finder: timerButton, view: brewScrollable);
  final minutesController = $.tester
      .widget<TextFormField>(durationMinutes)
      .controller!;
  final secondsController = $.tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, 'Seconds'))
      .controller!;
  int elapsed() =>
      int.parse(minutesController.text) * 60 +
      int.parse(secondsController.text);
  await $.tap(timerButton);
  await Future<void>.delayed(const Duration(seconds: 2));
  await $.tester.pump();
  final beforeScroll = elapsed();
  final position = $.tester.state<ScrollableState>(brewScrollable).position;
  position.jumpTo(0);
  await $.tester.pumpAndSettle();
  expect(timerButton.hitTestable(), findsNothing);
  await Future<void>.delayed(const Duration(seconds: 3));
  await $.tester.pump();
  expect(elapsed(), greaterThan(beforeScroll));
  await $.scrollUntilVisible(finder: timerButton, view: brewScrollable);
  expect(find.text('Stop'), findsOneWidget);
  await $.tap(timerButton);
  // The recipe header above the form leaves less room: bring the field in.
  await $.scrollUntilVisible(finder: durationMinutes, view: brewScrollable);
  await $.enterText(durationMinutes, '2');
  final durationSeconds = find.widgetWithText(TextFormField, 'Seconds');
  await $.scrollUntilVisible(finder: durationSeconds, view: brewScrollable);
  await $.enterText(durationSeconds, '35');
  final brewOutput = find.widgetWithText(TextFormField, 'Beverage weight (g)');
  await $.scrollUntilVisible(finder: brewOutput, view: brewScrollable);
  await $.enterText(brewOutput, '258');
  final tdsField = find.widgetWithText(TextFormField, 'TDS (%)');
  await $.scrollUntilVisible(finder: tdsField, view: brewScrollable);
  await $.enterText(tdsField, '1.35');
  final notesField = find.widgetWithText(TextFormField, 'Notes');
  await $.scrollUntilVisible(finder: notesField, view: brewScrollable);
  await $.enterText(notesField, 'Next: grind finer');
  await $.tap(find.text('Save').last);

  final brews = await database.select(database.brews).get();
  expect(brews, hasLength(1));
  expect(brews.single.methodName, 'V60');
  expect(brews.single.doseGrams, 18);
  expect(brews.single.beverageGrams, 258);
  expect(brews.single.tdsPercent, 1.35);
  expect(brews.single.methodId, isNotNull);
  expect(brews.single.grinderId, isNotNull);
  expect(brews.single.grindSetting, '22 clicks');
  final firstSelections = await database
      .select(database.brewToolSelections)
      .get();
  expect(firstSelections, hasLength(1));
  final firstTool = await database.select(database.methodTools).getSingle();
  expect(firstTool.name, 'Filter paper');
  expect(brews.single.lotId, isNotNull);
  final lots = await database.select(database.coffeeLots).get();
  expect(lots.single.remainingGrams, 232);
}

/// Home shows the last brew and the bean; the brew details show its
/// ratio, time and place on the sensory map.
Future<void> checkHomeAndBrewDetails(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final coffees = await database.select(database.coffees).get();
  // Home: relative last brew tile and the bean carousel.
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Home'),
    ),
  );
  // The week's brews replaced the last-brew time among Home's figures.
  await $.waitUntilVisible(find.byKey(const ValueKey('home-week-brews')));
  final homeBean = find.byKey(ValueKey('home-coffee-${coffees.single.id}'));
  await $.scrollUntilVisible(
    finder: homeBean,
    view: verticalScrollable(find.byType(Scaffold).first),
  );
  expect(
    find.descendant(of: homeBean, matching: find.text('232 g')),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('home-coffees');
  // The coffee's name opens its details; its recipe would open the brew.
  await $.tap(
    find.descendant(of: homeBean, matching: find.text(coffees.single.name)),
  );
  await $.waitUntilVisible(find.text('Price per kg'));
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.tap(find.text('Patrol Kenya').first);
  final detailsScrollable = find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  final mapButton = find.byKey(const ValueKey('open-sensory-map-button'));
  await $.waitUntilVisible(find.byKey(const ValueKey('brew-detail-edit')));
  await $.scrollUntilVisible(
    finder: find.text('Ratio'),
    view: detailsScrollable,
  );
  await $.waitUntilVisible(find.text('1:15.3'));
  await $.waitUntilVisible(find.text('Time'));
  await $.waitUntilVisible(find.text('2:35'));
  expect(
    find.descendant(
      of: find.byType(StatGrid),
      matching: find.text('22 clicks'),
    ),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('brew-details-ratio');
  await $.scrollUntilVisible(finder: mapButton, view: detailsScrollable);
  await $.tap(mapButton);
  await $.waitUntilVisible(find.byType(SensoryMapPage));
  final sensoryMarker = find.byKey(const ValueKey('sensory-map-marker'));
  expect(sensoryMarker, findsOneWidget);
  final markerSemantics = $.tester.widget<Semantics>(sensoryMarker);
  expect(markerSemantics.properties.label, 'EY 19.35%, TDS 1.35%');
  await $.tester.pump(const Duration(seconds: 5));
  await $.tester.pumpAndSettle();
  await $.takeNativeScreenshot('sensory-map-brew');
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
}

/// Rates the brew with the compass, a flavour score and a rating.
Future<void> rateFirstBrew(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  // Rate with the extraction compass, one flavour score and a rating.
  await $.tap(find.byKey(const ValueKey('brew-detail-rate')));
  final rateSheet = find.byKey(const ValueKey('rate-brew-sheet'));
  await $.waitUntilVisible(rateSheet);
  final rateScrollable = verticalScrollable(rateSheet);
  final rateSlider = find.descendant(
    of: rateSheet,
    matching: find.byType(Slider),
  );
  await $.scrollUntilVisible(finder: rateSlider, view: rateScrollable);
  await tapSliderAt($.tester, rateSlider, 0.75);
  await $.tester.pumpAndSettle();
  await $.waitUntilVisible(find.text('Rating: 7.5 / 10'));
  final sourCell = find.byKey(const ValueKey('compass--1-0'));
  await $.scrollUntilVisible(finder: sourCell, view: rateScrollable);
  await $.tap(sourCell);
  await $.waitUntilVisible(find.textContaining('Extract more'));
  final acidity = find.byKey(const ValueKey('score-Acidity-4'));
  await $.scrollUntilVisible(finder: acidity, view: rateScrollable);
  await $.tap(acidity);
  await $.takeNativeScreenshot('rate-brew-sheet');
  await $.tap(find.byKey(const ValueKey('rate-brew-save')));
  await $.tester.pumpAndSettle();
  final ratedBrew = await database.select(database.brews).getSingle();
  expect(ratedBrew.rating, 7.5);
  expect(ratedBrew.tasteBalance, -1);
  expect(ratedBrew.tasteStrength, 0);
  expect(ratedBrew.acidity, 4);

  await $.tap(find.text('Patrol Kenya').first);
  final compassLabel = find.byKey(const ValueKey('brew-detail-compass'));
  await $.scrollUntilVisible(
    finder: compassLabel,
    view: verticalScrollable(find.byType(BottomSheet)),
  );
  expect($.tester.widget<Text>(compassLabel).data, 'Too sour');
  await $.takeNativeScreenshot('brew-detail-tasting');
  await $.platformAutomator.android.pressBack();
  await $.tester.pumpAndSettle();
}

/// Repeats the brew keeping the recipe, switching to pre-ground.
Future<void> repeatPreGround(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final firstBrew = (await database.select(database.brews).get()).single;
  await $.tap(find.byTooltip('Actions'));
  await $.tap(find.text('Repeat'));
  await $.tester.pumpAndSettle();
  expect(find.text('Inventory lot'), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsNothing);
  final repeatScrollable = find
      .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
      .first;
  final repeatedMethod = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Choose a method',
  );
  final repeatedGrinder = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Grinder',
  );
  await $.scrollUntilVisible(finder: repeatedMethod, view: repeatScrollable);
  expect(
    $.tester
        .widget<DropdownButtonFormField<String>>(repeatedMethod)
        .initialValue,
    firstBrew.methodId,
  );
  final repeatedToolChip = find.widgetWithText(FilterChip, 'Filter paper');
  await $.scrollUntilVisible(finder: repeatedToolChip, view: repeatScrollable);
  expect($.tester.widget<FilterChip>(repeatedToolChip).selected, isTrue);
  await $.scrollUntilVisible(finder: repeatedGrinder, view: repeatScrollable);
  expect(
    $.tester
        .widget<DropdownButtonFormField<String>>(repeatedGrinder)
        .initialValue,
    firstBrew.grinderId,
  );
  final repeatedGrindSetting = find.widgetWithText(
    TextFormField,
    'Grind setting',
  );
  await $.scrollUntilVisible(
    finder: repeatedGrindSetting,
    view: repeatScrollable,
  );
  expect(
    $.tester.widget<TextFormField>(repeatedGrindSetting).controller!.text,
    '22 clicks',
  );
  final repeatedMinutes = find.widgetWithText(TextFormField, 'Minutes');
  await $.scrollUntilVisible(finder: repeatedMinutes, view: repeatScrollable);
  expect($.tester.widget<TextFormField>(repeatedMinutes).controller!.text, '');
  expect(
    $.tester
        .widget<InputDecorator>(
          find.descendant(
            of: repeatedMinutes,
            matching: find.byType(InputDecorator),
          ),
        )
        .decoration
        .helperText,
    'Starting recipe: 2:35',
  );
  final repeatedSeconds = find.widgetWithText(TextFormField, 'Seconds');
  await $.scrollUntilVisible(finder: repeatedSeconds, view: repeatScrollable);
  expect($.tester.widget<TextFormField>(repeatedSeconds).controller!.text, '');
  final repeatedYield = find.widgetWithText(
    TextFormField,
    'Beverage weight (g)',
  );
  await $.scrollUntilVisible(finder: repeatedYield, view: repeatScrollable);
  expect($.tester.widget<TextFormField>(repeatedYield).controller!.text, '');
  expect(
    $.tester
        .widget<InputDecorator>(
          find.descendant(
            of: repeatedYield,
            matching: find.byType(InputDecorator),
          ),
        )
        .decoration
        .helperText,
    'Starting recipe: 258 g',
  );
  final repeatedNotes = find.widgetWithText(TextFormField, 'Notes');
  await $.scrollUntilVisible(finder: repeatedNotes, view: repeatScrollable);
  expect(
    $.tester.widget<TextFormField>(repeatedNotes).controller!.text,
    'Next: grind finer',
  );
  // The grinder sits above the yield in the form.
  await $.scrollUntilVisible(
    finder: repeatedGrinder,
    view: repeatScrollable,
    scrollDirection: AxisDirection.up,
  );
  await $.tap(repeatedGrinder);
  await $.tap(find.text('Pre-ground').last);
  await $.tester.pumpAndSettle();
  expect(find.widgetWithText(TextFormField, 'Grind setting'), findsNothing);
  await $.tap(find.text('Save'));

  final brews = await database.select(database.brews).get();
  expect(brews, hasLength(2));
  final repeatedBrew = brews.singleWhere((brew) => brew.isPreGround);
  expect(repeatedBrew.grinderId, isNull);
  expect(repeatedBrew.grinderName, isNull);
  expect(repeatedBrew.grindSetting, isNull);
  expect(repeatedBrew.beverageGrams, isNull);
  expect(repeatedBrew.timeSeconds, isNull);
  expect(repeatedBrew.notes, 'Next: grind finer');
  final lots = await database.select(database.coffeeLots).get();
  expect(lots.single.remainingGrams, 214);
}
