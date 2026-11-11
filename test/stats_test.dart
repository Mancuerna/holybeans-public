import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/stats/stats_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

final _now = DateTime(2026, 9, 30, 18);

Future<AppDatabase> _journal() async {
  final database = memoryDatabase();
  final repository = JournalRepository(database);
  final kenya = await repository.createCoffeeWithComponents(
    name: 'Kenya',
    roaster: 'North',
    components: const [CoffeeComponentInput(country: 'Kenia')],
  );
  final blend = await repository.createCoffeeWithComponents(
    name: 'Blend',
    roaster: 'south ',
    components: const [
      CoffeeComponentInput(country: 'Kenya'),
      CoffeeComponentInput(country: 'Brasil'),
    ],
  );
  Future<void> brew(
    String coffeeId,
    int daysAgo, {
    String method = 'V60',
    double? dose,
    double? rating,
    int? balance,
    int? strength,
  }) async {
    final id = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: method,
      doseGrams: dose,
      brewedAt: _now.subtract(Duration(days: daysAgo)),
    );
    if (rating != null || balance != null) {
      await repository.rateBrew(
        id,
        rating: rating,
        notes: null,
        tasting: BrewTasting(balance: balance, strength: strength),
      );
    }
  }

  await brew(kenya, 0, dose: 18, rating: 8, balance: -1, strength: 0);
  await brew(kenya, 1, dose: 20, rating: 9, balance: -1, strength: 0);
  await brew(kenya, 2, method: 'Espresso', dose: 17, rating: 7);
  await brew(blend, 5, dose: 15, rating: 6, balance: 0, strength: 0);
  await brew(blend, 40, dose: 15);
  return database;
}

void main() {
  test('streaks count consecutive local days', () {
    DateTime day(int daysAgo) =>
        statsDay(_now.subtract(Duration(days: daysAgo)));
    final counts = {day(1): 2, day(2): 1, day(3): 1, day(6): 1};
    // No brew yet today: the streak still runs from yesterday.
    expect(currentStreak(counts, _now), 3);
    expect(currentStreak({day(2): 1}, _now), 0);
    expect(longestStreak(counts), 3);
    expect(longestStreak(const {}), 0);
  });

  test(
    'stats follow the range and group origins, roasters and styles',
    () async {
      final database = await _journal();
      addTearDown(database.close);
      final brews = await database.select(database.brews).get();
      final coffees = await database.select(database.coffees).get();
      final components = await database.select(database.coffeeComponents).get();
      BrewStats compute(StatsRange range) => brewStatsFromRows(
        brews: brews,
        coffees: coffees,
        components: components,
        styleOf: (brew) => brew.methodName == 'Espresso'
            ? BrewStyle.espresso
            : BrewStyle.filter,
        range: range,
        now: _now,
        languageCode: 'es',
      );

      final week = compute(StatsRange.week);
      expect(week.count, 4);
      expect(week.groundGrams, 70);
      expect(week.averageDose, 17.5);
      expect(week.brewsPerDay, closeTo(4 / 7, 1e-9));
      expect(week.averageRating, 7.5);
      expect(week.compass[(-1, 0)]!.count, 2);
      expect(week.compass[(-1, 0)]!.averageRating, 8.5);
      expect(week.compass[(0, 0)]!.count, 1);
      expect(week.methods.map((item) => (item.label, item.count)), [
        ('V60', 3),
        ('Espresso', 1),
      ]);
      // Kenia and Kenya are one country, named in the app language.
      expect(week.origins.map((item) => (item.label, item.count, item.flag)), [
        ('Kenia', 4, '🇰🇪'),
        ('Brasil', 1, '💀'),
      ]);
      expect(week.roasters.map((item) => (item.label, item.count)), [
        ('North', 3),
        ('south', 1),
      ]);
      expect(week.topRatedBeans.single.label, 'Kenya');
      expect(week.topRatedBeans.single.averageRating, 8);
      expect(
        week.ratingByStyle[BrewStyle.filter]!.averageRating,
        closeTo(23 / 3, 1e-9),
      );
      expect(week.ratingByStyle[BrewStyle.espresso]!.count, 1);

      final all = compute(StatsRange.all);
      expect(all.count, 5);
      expect(all.days, 41);
    },
  );

  test('daily averages start with the journal, retaining idle days', () async {
    final database = await _journal();
    addTearDown(database.close);
    final all = await database.select(database.brews).get();
    final recent = all
        .where(
          (b) =>
              DateTime.fromMillisecondsSinceEpoch(b.brewedAtMs)
                  .isAfter(_now.subtract(const Duration(days: 6))),
        )
        .toList();
    BrewStats compute(List<Brew> brews, StatsRange range) => brewStatsFromRows(
      brews: brews,
      coffees: const [],
      components: const [],
      styleOf: (_) => BrewStyle.filter,
      range: range,
      now: _now,
      languageCode: 'en',
    );
    for (final range in StatsRange.values) {
      final stats = compute(recent.reversed.toList(), range);
      expect(stats.days, 6);
      expect(stats.brewsPerDay, closeTo(4 / 6, 1e-9));
      expect(compute([], range).brewsPerDay, isNull);
      final today = compute([recent.first], range);
      expect(today.days, 1);
      expect(today.brewsPerDay, 1);
    }
    // The older entry establishes that this diary predates the week/month.
    expect(compute(all, StatsRange.week).days, 7);
    expect(compute(all, StatsRange.month).days, 30);
    expect(compute(all, StatsRange.year).days, 41);
    final idle = compute([all.last], StatsRange.week);
    expect(idle.count, 0);
    expect(idle.days, 7);
    expect(idle.brewsPerDay, 0);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('stats page shows activity, extraction map and favourites '
        '(text x$textScale)', (tester) async {
      final database = await _journal();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final brews = await database.select(database.brews).get();
      final coffees = await database.select(database.coffees).get();
      final components = await database.select(database.coffeeComponents).get();

      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: StatsPage(
            coffees: coffees,
            brews: brews,
            components: components,
            methods: const [],
            remainingGrams: 300,
            frozenGrams: 100,
            now: _now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('400 g'), findsOneWidget);
      expect(find.textContaining('100 g frozen'), findsOneWidget);
      // Opening statistics includes the first brew, even beyond 30 days.
      final overview = find.byKey(const ValueKey('stats-overview'));
      expect(
        find.descendant(of: overview, matching: find.text('5')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('stats-range-month')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: overview, matching: find.text('4')),
        findsOneWidget,
      );
      var list = find.byKey(const ValueKey('stats-list'));
      Future<void> reveal(Finder finder) async {
        await tester.scrollUntilVisible(
          finder,
          150,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
      }

      Future<void> openTab(String name, String listKey) async {
        final tab = find.descendant(
          of: find.byKey(const ValueKey('stats-tabs')),
          matching: find.text(name),
        );
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        list = find.byKey(ValueKey(listKey));
      }

      final today = find.byKey(const ValueKey('activity-2026-9-30-1'));
      await reveal(today);
      expect(
        find.byKey(const ValueKey('activity-2026-9-28-1')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Streak: 3 days, Longest: 3 days'),
        findsOneWidget,
      );

      await openTab('Brews', 'stats-list-brews');
      final sour = find.byKey(const ValueKey('stats-compass--1-0'));
      await reveal(sour);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Too sour: 2 brews, 8.5 / 10',
        ),
        findsOneWidget,
      );

      await openTab('Coffees', 'stats-list-beans');
      final origin = find.byKey(const ValueKey('stats-origins-0'));
      await reveal(origin);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: origin, matching: find.byType(Text)).first,
            )
            .textSpan!
            .toPlainText(includeSemanticsLabels: false),
        '🇰🇪  Kenya',
      );
      expect(tester.takeException(), isNull);

      // The 40-day-old brew only appears with a longer range.
      await openTab('Overview', 'stats-list');
      tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stats-range-all')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-overview')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty period says so', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('es'),
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
    await tester.pumpAndSettle();
    expect(find.text('No hay preparaciones en este periodo.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-activity')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats stay up to date while open', (tester) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Live',
      roaster: 'Roaster',
    );
    await repository.createBrew(coffeeId: coffeeId, methodName: 'V60');

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stats'));
    await tester.pumpAndSettle();
    final overview = find.byKey(const ValueKey('stats-overview'));
    expect(find.descendant(of: overview, matching: find.text('1')), findsOne);

    await tester.runAsync(
      () => repository.createBrew(coffeeId: coffeeId, methodName: 'V60'),
    );
    await tester.pumpAndSettle();
    expect(find.descendant(of: overview, matching: find.text('2')), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('the overview compares each figure with the period before', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffee = await repository.createCoffee(name: 'C', roaster: 'R');
    // Two brews this week, one the week before.
    for (final daysAgo in [0, 1, 8]) {
      await repository.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        doseGrams: 15,
        brewedAt: _now.subtract(Duration(days: daysAgo)),
      );
    }
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: StatsPage(
          coffees: await database.select(database.coffees).get(),
          brews: await database.select(database.brews).get(),
          components: const [],
          methods: const [],
          remainingGrams: 0,
          frozenGrams: 0,
          now: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-range')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats-range-week')));
    await tester.pumpAndSettle();
    final overview = find.byKey(const ValueKey('stats-overview'));
    expect(
      find.descendant(
        of: overview,
        matching: find.text('+100% vs previous period'),
      ),
      findsWidgets,
    );
    // All time has nothing before it.
    await tester.tap(find.byKey(const ValueKey('stats-range-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('vs previous period'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
