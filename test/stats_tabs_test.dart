import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/stats/stats_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

final _now = DateTime(2026, 9, 30, 18);

void main() {
  for (final (language, textScale) in [
    ('en', 1.0),
    ('en', 2.0),
    ('es', 1.0),
    ('es', 2.0),
  ]) {
    final strings = lookupAppLocalizations(Locale(language));
    testWidgets('the coffee, brew and cost tabs show their charts '
        '($language, text x$textScale)', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final espresso = await repository.createMethod(
        name: 'Lelit',
        category: 'espresso',
      );
      final v60 = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      Future<String> coffee(String name, int cents, String process) =>
          repository.createCoffee(
            name: name,
            roaster: 'Roaster $name',
            initialGrams: 250,
            paidPriceCents: cents,
            roastDate: '2026-09-01',
            process: process,
            variety: 'Caturra',
          );
      final dear = await coffee('Gesha', 4000, 'Natural');
      final cheap = await coffee('Brazil', 1200, 'Washed');
      final mid = await coffee('Kenya', 2000, 'Washed');
      var day = 10;
      Future<void> brew(
        String coffeeId,
        String method, {
        required double rating,
        required int seconds,
        double celsius = 93,
      }) async {
        final lot = (await repository.coffeeLots(coffeeId)).single.id;
        final id = await repository.createBrew(
          coffeeId: coffeeId,
          lotId: lot,
          methodId: method,
          methodName: method == espresso ? 'Lelit' : 'V60',
          doseGrams: method == espresso ? 18 : 15,
          beverageGrams: method == espresso ? 36 : null,
          waterGrams: method == espresso ? null : 250,
          timeSeconds: seconds,
          temperatureC: celsius,
          brewedAt: DateTime(2026, 9, day++, 9),
        );
        await repository.rateBrew(
          id,
          rating: rating,
          notes: null,
          tasting: const BrewTasting(),
        );
      }

      await brew(dear, espresso, rating: 9, seconds: 28);
      await brew(dear, espresso, rating: 9.5, seconds: 31, celsius: 95);
      await brew(cheap, v60, rating: 6, seconds: 180, celsius: 90);
      await brew(cheap, v60, rating: 7, seconds: 215);
      await brew(mid, espresso, rating: 8, seconds: 36);
      await brew(mid, v60, rating: 8.5, seconds: 200);
      final brews = await database.select(database.brews).get();
      final coffees = await database.select(database.coffees).get();
      final lots = await database.select(database.coffeeLots).get();
      final components = await database.select(database.coffeeComponents).get();
      final methods = await database.select(database.brewMethods).get();

      await tester.pumpWidget(
        localizedApp(
          locale: Locale(language),
          home: StatsPage(
            coffees: coffees,
            brews: brews,
            components: components,
            methods: methods,
            lots: lots,
            pricePerKg: pricePerKgByCoffee(coffees, lots),
            remainingGrams: 500,
            frozenGrams: 0,
            now: _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final overviewGrid = find.byKey(const ValueKey('stats-overview'));
      final inventoryNote = find.byKey(const ValueKey('stats-inventory-note'));
      await tester.scrollUntilVisible(
        inventoryNote,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('stats-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text(strings.statsCurrentInventoryNote), findsOneWidget);
      expect(find.text(strings.statsIncludesArchived), findsOneWidget);
      expect(
        tester.getRect(inventoryNote).left,
        tester.getRect(overviewGrid).left,
      );
      expect(
        tester.getRect(inventoryNote).right,
        tester.getRect(overviewGrid).right,
      );
      expect(
        tester.getRect(inventoryNote).top,
        greaterThanOrEqualTo(tester.getRect(overviewGrid).bottom),
      );

      Future<void> openTab(String name) async {
        final tab = find.descendant(
          of: find.byKey(const ValueKey('stats-tabs')),
          matching: find.text(name),
        );
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
      }

      Future<void> reveal(String list, Finder target) async {
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(ValueKey(list)),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      await reveal(
        'stats-list',
        find.byKey(const ValueKey('stats-brews-per-period')),
      );

      await openTab(strings.statsTabBeans);
      final firstCup = find.byKey(const ValueKey('stats-beans-overview'));
      expect(
        find.descendant(
          of: firstCup,
          matching: find.text(strings.statsDaysAfterRoast(11)),
        ),
        findsOneWidget,
        reason: 'roasted on the 1st; first brews 9, 11 and 13 days later',
      );
      await reveal(
        'stats-list-beans',
        find.byKey(const ValueKey('stats-processes-0')),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-processes-0')),
          matching: find.text('Washed'),
        ),
        findsOneWidget,
      );

      await openTab(strings.statsTabBrews);
      final grid = find.byKey(const ValueKey('stats-brews-overview'));
      expect(find.descendant(of: grid, matching: find.text('1:2')), findsOne);
      await reveal(
        'stats-list-brews',
        find.byKey(const ValueKey('stats-shot-times')),
      );
      await reveal(
        'stats-list-brews',
        find.byKey(const ValueKey('stats-learning-curve')),
      );
      await reveal(
        'stats-list-brews',
        find.byKey(const ValueKey('stats-rating-by-temperature')),
      );

      await openTab(strings.statsTabCosts);
      await reveal(
        'stats-list-costs',
        find.byKey(const ValueKey('stats-cost-vs-rating')),
      );
      // Tapping a dot says which coffee it is.
      final scatter = find.byKey(const ValueKey('stats-cost-vs-rating'));
      final box = tester.getRect(
        find.descendant(of: scatter, matching: find.byType(CustomPaint)).last,
      );
      // The dearest coffee sits at the right, near the top.
      await tester.tapAt(
        Offset(box.right - 8 - box.width * 0.07, box.top + 20),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Gesha:'), findsOneWidget);
      await reveal(
        'stats-list-costs',
        find.byKey(const ValueKey('stats-best-value-0')),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-best-value-0')),
          matching: find.text('Kenya'),
        ),
        findsOneWidget,
        reason: 'rated at the median or above, and cheaper than the Gesha',
      );
      await reveal(
        'stats-list-costs',
        find.byKey(const ValueKey('stats-roaster-price-0')),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-roaster-price-0')),
          matching: find.text('Roaster Gesha'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('costs ask for prices when there are none', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: StatsPage(
          coffees: const [],
          brews: const [],
          components: const [],
          methods: const [],
          remainingGrams: 0,
          frozenGrams: 0,
          now: _now,
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('stats-tabs')),
        matching: find.text('Costs'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-no-prices')), findsOneWidget);
  });
}
