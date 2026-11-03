import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

Future<void> checkBrewPours(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final coffee = await repo.createCoffee(
    name: 'Patrol pours',
    roaster: 'Fixture',
    initialGrams: 250,
  );
  await repo.createMethod(name: 'V60', category: 'pourover');
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await $.tap(find.text('Brew'));
  final bean = find.byKey(const ValueKey('brew-coffee-picker'));
  await $.tap(bean);
  await $.tap(find.text('Patrol pours').last);
  final method = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.decoration.labelText == 'Choose a method',
  );
  await $.tap(method);
  await $.tap(find.text('V60').last);

  Future<void> show(Finder target) async {
    // The form keeps its sections mounted; reveal the actual field instead
    // of guessing a drag direction after the keyboard changes its viewport.
    await $.tester.ensureVisible(target);
    await $.pumpAndSettle();
    await $.waitUntilVisible(target);
  }

  Future<void> enter(Finder field, String value) async {
    await show(field);
    await $.enterText(field, value);
  }

  Finder count(String label) => find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField<int> && w.decoration.labelText == label,
  );
  Future<void> chooseCount(String label, int n) async {
    await show(count(label));
    await $.tap(count(label));
    final choice = find.text('$n').last;
    await $.scrollUntilVisible(
      finder: choice,
      view: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await $.tap(choice);
  }

  await enter(find.widgetWithText(TextFormField, 'Dose (g)'), '18');
  await enter(find.widgetWithText(TextFormField, 'Water (g)'), '270');
  await enter(find.widgetWithText(TextFormField, 'Minutes'), '3');
  await enter(find.widgetWithText(TextFormField, 'Seconds'), '0');
  await chooseCount('Blooms', 0);
  await chooseCount('Pours', 3);
  expect(find.widgetWithText(TextFormField, 'Water added (g)'), findsNothing);
  await $.takeNativeScreenshot('filter-pour-counts');
  await $.tap(find.text('Save').last);
  var brew = await database.select(database.brews).getSingle();
  expect(brew.bloomCount, 0);
  expect(brew.pourCount, 3);
  expect(brew.pourPhasesJson, isNull);
  expect((await repo.coffeeLots(coffee)).single.remainingGrams, 232);

  // Simulate a saved recipe with an old aggregate bloom time, without a count.
  await (database.update(
    database.brews,
  )..where((b) => b.id.equals(brew.id))).write(
    const BrewsCompanion(bloomCount: Value(null), bloomSeconds: Value(45)),
  );

  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  await $.tap(find.byTooltip('Actions'));
  await $.tap(find.text('Edit'));
  await chooseCount('Blooms', 2);
  await chooseCount('Pours', 10);
  final details = find.byKey(const ValueKey('brew-pour-details'));
  await show(details);
  expect(
    find.widgetWithText(TextFormField, 'Total bloom time (s)'),
    findsNothing,
  );
  await $.tap(find.text('Bloom and pour details'));
  final total = find.widgetWithText(TextFormField, 'Total bloom time (s)');
  await show(total);
  expect($.tester.widget<TextFormField>(total).controller!.text, '45');
  await enter(find.byKey(const ValueKey('bloom-1-water')), '36');
  await enter(
    find.descendant(
      of: find.byKey(const ValueKey('bloom-1-duration')),
      matching: find.byType(TextFormField),
    ),
    '8',
  );
  await enter(
    find.descendant(
      of: find.byKey(const ValueKey('bloom-1-rest')),
      matching: find.byType(TextFormField),
    ),
    '30',
  );
  await show(find.byKey(const ValueKey('bloom-1-water')));
  await $.takeNativeScreenshot('filter-bloom-fields-spacing');
  await enter(find.byKey(const ValueKey('pour-10-water')), '50');
  await enter(
    find.descendant(
      of: find.byKey(const ValueKey('pour-10-duration')),
      matching: find.byType(TextFormField),
    ),
    '9',
  );
  await $.takeNativeScreenshot('filter-pour-last-detail-keyboard');
  await $.tap(find.text('Save').last);
  brew = await database.select(database.brews).getSingle();
  expect(brew.bloomCount, 2);
  expect(brew.pourCount, 10);
  expect(brew.bloomSeconds, 45);
  final phases = BrewPours.fromStorage(
    bloomCount: 2,
    pourCount: 10,
    phasesJson: brew.pourPhasesJson,
  ).phases;
  expect(phases.first.restSeconds, 30);
  expect(phases.last.waterGrams, 50);
  expect(phases.last.durationSeconds, 9);
  expect((await repo.coffeeLots(coffee)).single.remainingGrams, 232);

  await $.tap(find.text('Patrol pours').first);
  final recorded = find.byKey(const ValueKey('brew-recorded-pour-details'));
  await $.scrollUntilVisible(
    finder: recorded,
    view: verticalScrollable(find.byType(BottomSheet)),
  );
  expect(find.text('Pour 10'), findsNothing);
  await $.tap(find.text('Bloom and pour details'));
  await $.scrollUntilVisible(
    finder: find.text('Pour 10'),
    view: verticalScrollable(find.byType(BottomSheet)),
  );
  await $.takeNativeScreenshot('filter-recorded-pour-details');
  await $.platformAutomator.android.pressBack();
  await $.tap(find.byTooltip('Actions'));
  await $.tap(find.text('Repeat'));
  await show(count('Blooms'));
  expect(
    $.tester.widget<DropdownButtonFormField<int>>(count('Blooms')).initialValue,
    2,
  );
  expect(
    $.tester.widget<DropdownButtonFormField<int>>(count('Pours')).initialValue,
    10,
  );
  expect(find.widgetWithText(TextFormField, 'Water added (g)'), findsNothing);
  await $.tap(find.text('Save').last);
  final repeated = (await database.select(database.brews).get()).singleWhere(
    (b) => b.id != brew.id,
  );
  expect(repeated.bloomCount, 2);
  expect(repeated.pourCount, 10);
  expect(repeated.pourPhasesJson, isNull);
  expect(repeated.timeSeconds, isNull);
}
