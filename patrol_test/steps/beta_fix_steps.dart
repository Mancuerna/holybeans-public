import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:patrol/patrol.dart';

import '../support/smoke_support.dart';

/// Exercises sorting, suggestions, the low-stock offer and machine results
/// against synthetic data in the isolated Patrol database.
Future<void> checkBetaFixes(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final source = await repository.createCoffeeWithComponents(
    name: 'Suggestion source',
    roaster: 'HolyBeans smoke test',
    components: const [CoffeeComponentInput(producer: 'Edwin Noreña')],
  );
  await repository.setCoffeeArchived(source, archived: true);
  final coffeeId = await repository.createCoffee(
    name: 'Alpha fixture',
    roaster: 'Test',
    initialGrams: 250,
  );
  await repository.createMethod(name: 'V60', category: 'pourover');
  await repository.createMethod(
    name: 'Meticulous',
    category: 'espresso',
    machine: 'meticulous',
    machineAddress: 'meticulous.test',
  );
  final older = await repository.createBrew(
    coffeeId: coffeeId,
    methodName: 'V60',
    brewedAt: DateTime.now().subtract(const Duration(days: 2)),
  );
  final newer = await repository.createBrew(
    coffeeId: coffeeId,
    methodName: 'V60',
    brewedAt: DateTime.now().subtract(const Duration(days: 1)),
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await _tab($, 'Brews');
  expect($.tester.widget<BrewCard>(find.byType(BrewCard).first).brew.id, newer);
  await $.tap(find.byKey(const ValueKey('history-sort')));
  await $.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Ascending'));
  expect($.tester.widget<BrewCard>(find.byType(BrewCard).first).brew.id, older);
  await $.tap(find.byKey(const ValueKey('history-sort')));
  await $.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, 'Descending'));
  expect($.tester.widget<BrewCard>(find.byType(BrewCard).first).brew.id, newer);
  // Archived brews have their own button, outside the filters.
  final archived = find.byKey(const ValueKey('history-show-archived'));
  await $.tap(archived);
  expect($.tester.widget<FilterChip>(archived).selected, isTrue);
  await $.tap(archived);
  expect($.tester.widget<FilterChip>(archived).selected, isFalse);

  await _tab($, 'Beans');
  await $.tap(find.text('Add bean'));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Coffee name'),
    'Patrol low stock',
  );
  final roaster = find.widgetWithText(TextFormField, 'Roaster');
  await $.tap(roaster);
  await $.tester.enterText(roaster, 'Holy');
  await $.tester.pumpAndSettle();
  await $.tap(find.text('HolyBeans smoke test').last);
  final scroll = verticalScrollable(find.byType(CoffeeForm));
  final grams = find.widgetWithText(TextFormField, 'Purchased quantity (g)');
  await $.scrollUntilVisible(finder: grams, view: scroll);
  await $.enterText(grams, '35');
  final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
  await $.scrollUntilVisible(finder: addOrigin, view: scroll);
  await $.tap(addOrigin);
  final producer = find.widgetWithText(TextFormField, 'Producer');
  await $.scrollUntilVisible(finder: producer, view: scroll);
  await $.tap(producer);
  await $.tester.enterText(producer, 'Edwin nore');
  await $.tester.pumpAndSettle();
  await $.tap(find.text('Edwin Noreña').last);
  await $.takeNativeScreenshot('bean-producer-suggestion');
  await $.tap(find.text('Save').last);
  final bean = (await repository.allCoffees()).singleWhere(
    (row) => row.name == 'Patrol low stock',
  );
  expect(bean.roaster, 'HolyBeans smoke test');
  expect(
    (await repository.coffeeComponents(bean.id)).single.producer,
    'Edwin Noreña',
  );

  await $.tap(find.byKey(const ValueKey('bean-sort')));
  await $.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Descending'));
  expect(
    $.tester.getTopLeft(find.text('Patrol low stock')).dy,
    lessThan($.tester.getTopLeft(find.text('Alpha fixture')).dy),
  );
  // The order is kept when the app opens again.
  await $.pumpWidgetAndSettle(const SizedBox.shrink());
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await _tab($, 'Beans');
  expect(
    $.tester.getTopLeft(find.text('Patrol low stock')).dy,
    lessThan($.tester.getTopLeft(find.text('Alpha fixture')).dy),
  );
  await $.tap(find.byKey(const ValueKey('bean-sort')));
  await $.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Ascending'));
  expect(
    $.tester.getTopLeft(find.text('Alpha fixture')).dy,
    lessThan($.tester.getTopLeft(find.text('Patrol low stock')).dy),
  );

  await _brewBean($, 'Patrol low stock', 'V60');
  await _dose($, '20');
  await $.tap(find.text('Save').last);
  await $.waitUntilVisible(find.byKey(const ValueKey('coffee-archive-dialog')));
  expect(find.textContaining('average 20 g dose with V60'), findsOneWidget);
  await $.takeNativeScreenshot('low-stock-archive-offer');
  await $.tap(find.text('Cancel').last);
  expect((await repository.coffee(bean.id))!.archivedAtMs, isNull);

  final original = connectMeticulous;
  connectMeticulous = (_) => _FixtureMachine();
  try {
    await _brewBean($, 'Alpha fixture', 'Meticulous');
    final importButton = find.byKey(const ValueKey('brew-import-shot'));
    final brewScroll = verticalScrollable(find.byType(BrewForm));
    await $.scrollUntilVisible(finder: importButton, view: brewScroll);
    await $.tap(importButton);
    await $.tap(
      find.byKey(const ValueKey('meticulous-shot-patrol-first-drip')),
    );
    final firstDrip = find.widgetWithText(TextFormField, 'First drip (s)');
    await $.scrollUntilVisible(finder: firstDrip, view: brewScroll);
    expect($.tester.widget<TextFormField>(firstDrip).controller!.text, '4');
    await $.takeNativeScreenshot('meticulous-first-drip');
    await _dose($, '18', up: true);
    await $.tap(find.text('Save').last);
    final brew = (await repository.allBrews()).singleWhere(
      (brew) => brew.methodName == 'Meticulous',
    );
    expect(brew.firstDripSeconds, 4);
    expect(brew.timeSeconds, 20);
    expect(await repository.brewCurve(brew.id), isNotNull);

    // A filter brew takes the free pour from the same machine's scale.
    await _brewBean($, 'Alpha fixture', 'V60');
    final freePour = find.byKey(const ValueKey('brew-import-free-pour'));
    final filterScroll = verticalScrollable(find.byType(BrewForm));
    await $.scrollUntilVisible(finder: freePour, view: filterScroll);
    await $.tap(freePour);
    await $.tap(
      find.byKey(const ValueKey('meticulous-free-pour-patrol-free-pour')),
    );
    await $.waitUntilVisible(find.text('Free pour from the Meticulous'));
    await $.takeNativeScreenshot('meticulous-free-pour');
    await $.tap(find.text('Save').last);
    // The fixture already has older V60 brews of this bean.
    final filter = (await repository.allBrews())
        .where((brew) => brew.methodName == 'V60' && brew.coffeeId == coffeeId)
        .reduce((a, b) => a.createdAtMs >= b.createdAtMs ? a : b);
    expect((filter.doseGrams, filter.waterGrams), (15.0, 250.0));
    expect(
      (await repository.brewCurve(filter.id))?.source,
      ImportOperations.meticulousFreePourSource,
    );
  } finally {
    connectMeticulous = original;
  }
}

Future<void> _tab(PatrolIntegrationTester $, String label) => $.tap(
  find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
);

Future<void> _brewBean(
  PatrolIntegrationTester $,
  String name,
  String method,
) async {
  await $.tap(find.text(name));
  await $.scrollUntilVisible(
    finder: find.text('Brew with this bean'),
    view: verticalScrollable(find.byType(BottomSheet).last),
  );
  await $.tap(find.text('Brew with this bean'));
  final methodField = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Choose a method',
  );
  await $.scrollUntilVisible(
    finder: methodField,
    view: verticalScrollable(find.byType(BrewForm)),
  );
  await $.tap(methodField);
  await $.tap(find.text(method).last);
}

Future<void> _dose(
  PatrolIntegrationTester $,
  String value, {
  bool up = false,
}) async {
  final dose = find.widgetWithText(TextFormField, 'Dose (g)');
  await $.scrollUntilVisible(
    finder: dose,
    view: verticalScrollable(find.byType(BrewForm)),
    scrollDirection: up ? AxisDirection.up : AxisDirection.down,
  );
  await $.enterText(dose, value);
}

class _FixtureMachine implements MeticulousSource {
  final result = MeticulousShot.fromHistoryEntry({
    'id': 'patrol-first-drip',
    'time': DateTime.now().millisecondsSinceEpoch / 1000,
    'profile': {'name': 'Patrol profile', 'temperature': 93},
    'data': [
      for (final (ms, status, weight) in [
        (0, 'Preinfusion', 0.0),
        (4000, 'Brew', 0.1),
        (20000, 'retracting', 36.0),
      ])
        {
          'time': ms,
          'status': status,
          'shot': {'weight': weight, 'pressure': 8, 'flow': 2},
        },
    ],
  });

  @override
  Future<List<MeticulousShot>> recentShots({
    int limit = 50,
    bool withCurves = false,
  }) async => [result];
  @override
  Future<MeticulousShot> shot(String id) async => result;
  @override
  Future<String?> rating(String id) async => null;

  @override
  Future<MeticulousFreePour?> lastFreePour() async => MeticulousFreePour(
    id: 'patrol-free-pour',
    brewedAt: DateTime.now(),
    doseGrams: 15,
    waterGrams: 250,
    beverageGrams: 210,
    temperatureC: 94,
    timeSeconds: 180,
    pours: const [
      DetectedPour(startMs: 0, endMs: 6000, grams: 45),
      DetectedPour(startMs: 40000, endMs: 60000, grams: 205),
    ],
    curve: ShotCurve(
      timesMs: const [0, 6000, 40000, 60000, 180000],
      flow: const [0, 7.5, 0, 10, 0],
      weight: const [0, 45, 45, 250, 250],
    ),
  );
}
