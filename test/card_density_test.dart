import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('bean density and unified brew cards remain usable at 2x text', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Ethiopia Guji Natural',
      roaster: 'North Star Roasters',
      country: 'Ethiopia',
      region: 'Guji Uraga',
      roastDate: '2026-09-24',
      initialGrams: 250,
      roastLevel: 'light',
      notes: 'Bright citrus and jasmine',
    );
    await (database.update(database.coffees)
          ..where((coffee) => coffee.id.equals(coffeeId)))
        .write(const CoffeesCompanion(rating: Value(8.5)));
    final lotId = (await repository.coffeeLots(coffeeId)).single.id;
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final regularBrewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'V60',
      lotId: lotId,
      grinderName: 'Hand grinder',
      grindSetting: '18 clicks',
      doseGrams: 18,
      waterGrams: 288,
      beverageGrams: 252,
      timeSeconds: 180,
      rating: 7.5,
      notes: 'Sweet finish',
      brewedAt: DateTime(2026, 9, 29, 11),
    );
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tapBottomDestination(tester, 1);
    final beanSearch = find.byType(TextField).first;
    final beanMenu = find.byKey(const ValueKey('beans-view-menu'));
    final beanToggle = find.byKey(const ValueKey('bean-density-toggle'));
    final beanSort = find.byKey(const ValueKey('bean-sort'));
    _expectControlRowFits(tester, beanSearch, [beanMenu, beanSort]);
    final beanCard = find.byKey(ValueKey('bean-card-$coffeeId'));
    expect(beanCard, findsOneWidget);
    expect(
      find.descendant(of: beanCard, matching: find.text('North Star Roasters')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('bean-origin-$coffeeId')))
          .textSpan!
          .toPlainText(includeSemanticsLabels: false),
      '🇪🇹  Ethiopia, Guji Uraga',
    );
    expect(
      find.descendant(of: beanCard, matching: find.text('232 / 250 g')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Remaining: 232 g',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('bean-stock-$coffeeId')), findsOneWidget);
    expect(
      find.descendant(
        of: beanCard,
        matching: find.textContaining('Light, Roasted'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: beanCard, matching: find.text('8.5')),
      findsOneWidget,
    );
    // The description is for the details, not the list.
    expect(find.text('Bright citrus and jasmine'), findsNothing);

    await tester.tap(beanMenu);
    await tester.pumpAndSettle();
    expect(find.text('Compact cards'), findsOneWidget);
    await tester.tap(beanToggle);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('bean-stock-$coffeeId')), findsNothing);
    expect(find.textContaining('North Star Roasters, 232 g'), findsOneWidget);
    await tester.ensureVisible(find.text('Ethiopia Guji Natural'));
    await tester.tap(find.text('Ethiopia Guji Natural').last);
    await tester.pumpAndSettle();
    expect(find.text('Brew with this bean'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tapBottomDestination(tester, 2);
    final brewSearch = find.byType(TextField).first;
    final brewToggle = find.byKey(const ValueKey('brew-density-toggle'));
    final historySort = find.byKey(const ValueKey('history-sort'));
    _expectControlRowFits(tester, brewSearch, [historySort]);
    expect(brewToggle, findsNothing);
    // Large text moves the actions below the full-width search.
    expect(
      tester.getRect(find.byKey(const ValueKey('history-filter-button'))).top,
      greaterThanOrEqualTo(tester.getRect(brewSearch).bottom),
    );
    final regularCard = find.byKey(ValueKey('brew-card-$regularBrewId'));
    final historyScrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    final ratioFact = find.descendant(
      of: regularCard,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '18 g → 288 g, 1:16, 3:00',
      ),
    );
    expect(ratioFact, findsOneWidget);
    expect(
      find.descendant(
        of: regularCard,
        matching: find.text('Hand grinder · 18 clicks'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: regularCard, matching: find.text('Sweet finish')),
      findsNothing,
    );
    expect(
      find.descendant(of: regularCard, matching: find.text('7.5')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      ratioFact,
      180,
      scrollable: historyScrollable,
    );
    await tester.ensureVisible(ratioFact);
    await tester.pumpAndSettle();
    await tester.tap(ratioFact);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('brew-detail-edit')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.drag(historyScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    final actions = find.descendant(
      of: regularCard,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(regularCard);
    await tester.tap(regularCard);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('brew-detail-edit')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

void _expectControlRowFits(
  WidgetTester tester,
  Finder search,
  List<Finder> buttons,
) {
  final screenWidth = tester.view.physicalSize.width;
  final searchBounds = tester.getRect(search);
  var previousRight = 0.0;
  for (final button in buttons) {
    final bounds = tester.getRect(button);
    expect(bounds.left, greaterThanOrEqualTo(previousRight));
    expect(bounds.width, greaterThanOrEqualTo(48));
    expect(bounds.right, lessThanOrEqualTo(screenWidth));
    expect(bounds.top, greaterThanOrEqualTo(searchBounds.bottom));
    previousRight = bounds.right;
  }
}
