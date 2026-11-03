import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void main() {
  test('freeze spans read today, days and weeks', () {
    final s = lookupAppLocalizations(const Locale('en'));
    expect(dayOrWeekSpan(s, 0), 'Today');
    expect(dayOrWeekSpan(s, 1), '1 day');
    expect(dayOrWeekSpan(s, 13), '13 days');
    expect(dayOrWeekSpan(s, 20), '2 weeks');
  });

  Finder vertical() => find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .first;

  for (final textScale in [1.0, 2.0]) {
    testWidgets('home shows the week, oldest freeze and the coffee to repeat '
        '(text x$textScale)', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Undated bean with a rather long name',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 250,
      );
      final lotId = (await repository.coffeeLots(coffeeId)).single.id;
      await repository.freezeCoffee(
        lotId: lotId,
        grams: 100,
        frozenDate: _isoDate(DateTime.now().subtract(const Duration(days: 20))),
      );
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lotId,
        methodName: 'V60',
        doseGrams: 15,
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 brew'), findsOneWidget);
      expect(find.text('oldest 2 weeks'), findsOneWidget);
      // No roast date, but nothing else takes the room: it can be repeated.
      final tile = find.byKey(ValueKey('home-coffee-$coffeeId'));
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('home-repeat-$coffeeId')),
        200,
        scrollable: vertical(),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: tile, matching: find.text('135 g')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-group-undated')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ValueKey('home-repeat-$coffeeId')));
      await tester.pumpAndSettle();
      expect(find.byType(BrewForm), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  testWidgets('a long low-stock coffee name wraps to two lines', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = JournalRepository(database);
    const name = 'Hacienda Misiones eighty-eight with a very long coffee name';
    final coffeeId = await repository.createCoffee(
      name: name,
      roaster: 'Test roaster',
      initialGrams: 40,
    );
    final lotId = (await repository.coffeeLots(coffeeId)).single.id;
    for (var index = 0; index < 2; index++) {
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lotId,
        methodName: 'V60',
        doseGrams: 18,
      );
    }
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(ValueKey('low-stock-$coffeeId'));
    await tester.scrollUntilVisible(tile, 200, scrollable: vertical());
    final title = find.descendant(of: tile, matching: find.text(name));
    expect(title, findsOneWidget);
    final context = tester.element(title);
    final oneLine = TextPainter(
      text: TextSpan(text: name, style: DefaultTextStyle.of(context).style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: tester.getSize(title).width);
    expect(tester.getSize(title).height, greaterThan(oneLine.height + 1));
    oneLine.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('coffees are grouped by freshness and repeat their favourite', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final now = DateTime.now();
    String daysAgo(int days) => _isoDate(now.subtract(Duration(days: days)));
    final old = await repository.createCoffee(
      name: 'Old light',
      roaster: 'R',
      roastLevel: 'light',
      roastDate: daysAgo(70),
      initialGrams: 250,
    );
    final ready = await repository.createCoffee(
      name: 'Ready medium',
      roaster: 'R',
      roastLevel: 'medium',
      roastDate: daysAgo(15),
      initialGrams: 250,
    );
    await repository.createCoffee(
      name: 'Just roasted',
      roaster: 'R',
      roastDate: daysAgo(1),
      initialGrams: 250,
    );
    final brewedFresh = await repository.createCoffee(
      name: 'Brewed while resting',
      roaster: 'R',
      roastDate: daysAgo(1),
      initialGrams: 250,
    );
    await repository.createBrew(
      coffeeId: brewedFresh,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: now.subtract(const Duration(hours: 1)),
    );
    await repository.createBrew(
      coffeeId: old,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: now.subtract(const Duration(days: 3)),
    );
    final favorite = await repository.createBrew(
      coffeeId: ready,
      methodName: 'V60',
      doseGrams: 15,
      waterGrams: 250,
      brewedAt: now.subtract(const Duration(days: 2)),
    );
    await repository.setBrewFavorite(favorite, favorite: true);
    await repository.createBrew(
      coffeeId: ready,
      methodName: 'V60',
      doseGrams: 16,
      waterGrams: 260,
      brewedAt: now.subtract(const Duration(hours: 5)),
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    final soon = find.byKey(const ValueKey('home-group-spend-soon'));
    await tester.scrollUntilVisible(soon, 200, scrollable: vertical());
    expect(find.text('Use them soon · 1'), findsOneWidget);
    expect(find.text('Ready · 1'), findsOneWidget);
    final soonY = tester.getTopLeft(soon).dy;
    expect(
      tester.getTopLeft(find.byKey(ValueKey('home-coffee-$old'))).dy,
      greaterThan(soonY),
    );
    final readyTile = find.byKey(ValueKey('home-coffee-$ready'));
    await tester.scrollUntilVisible(readyTile, 200, scrollable: vertical());
    // Repeat starts from the favourite, not the newer brew.
    expect(
      find.descendant(
        of: readyTile,
        matching: find.textContaining('Favourite recipe'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: readyTile, matching: find.textContaining('250')),
      findsWidgets,
    );
    // A resting coffee already brewed can be repeated; the other is summed
    // up below it.
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('home-repeat-$brewedFresh')),
      200,
      scrollable: vertical(),
    );
    expect(find.text('Resting · 2'), findsOneWidget);
    final resting = find.byKey(const ValueKey('home-resting'));
    await tester.scrollUntilVisible(resting, 200, scrollable: vertical());
    expect(
      find.descendant(of: resting, matching: find.text('Others resting')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: resting, matching: find.textContaining('1 coffee')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
