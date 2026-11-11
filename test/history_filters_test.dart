import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en_GB'));

  testWidgets(
    'History filters combine, archived brews have their own button, and dates and unrated brews are handled',
    (tester) async {
      final database = memoryDatabase();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(database.close);
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'en',
        'GB',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

      final repository = JournalRepository(database);
      final alphaId = await repository.createCoffee(
        name: 'Alpha Bean',
        roaster: 'Test roaster',
      );
      final betaId = await repository.createCoffee(
        name: 'Beta Bean',
        roaster: 'Test roaster',
      );
      final today = DateTime.now();
      final todayAtTen = DateTime(today.year, today.month, today.day, 10);
      final yesterdayAtTen = todayAtTen.subtract(const Duration(days: 1));
      await repository.createBrew(
        coffeeId: alphaId,
        methodName: 'V60',
        rating: 8.5,
        brewedAt: todayAtTen,
      );
      await repository.createBrew(
        coffeeId: betaId,
        methodName: 'V60',
        brewedAt: todayAtTen,
      );
      await repository.createBrew(
        coffeeId: alphaId,
        methodName: 'V60',
        rating: 7.5,
        brewedAt: todayAtTen,
      );
      final archivedId = await repository.createBrew(
        coffeeId: alphaId,
        methodName: 'Espresso',
        rating: 7.5,
        brewedAt: yesterdayAtTen,
      );
      await repository.setBrewArchived(archivedId, archived: true);

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _openHistory(tester);

      expect(find.byType(Card), findsNWidgets(3));
      final archivedButton = find.byKey(
        const ValueKey('history-show-archived'),
      );
      expect(
        tester.widget<IconButton>(archivedButton).tooltip,
        'Show archived',
      );
      await tester.tap(archivedButton);
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(4));
      expect(
        tester.widget<IconButton>(archivedButton).tooltip,
        'Hide archived',
      );

      final filterButton = find.byKey(const ValueKey('history-filter-button'));
      expect(filterButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(filterButton).tooltip,
        'Filters',
        reason: 'archived brews are not a filter',
      );
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      expect(find.text('Show archived'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Filters'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Unrated brews are excluded only when a minimum rating is set.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('history-date-filter')),
      );
      await tester.tap(find.byKey(const ValueKey('history-date-filter')));
      await tester.pumpAndSettle();
      final dayLabel = '${todayAtTen.day}';
      expect(find.text('Select start date'), findsOneWidget);
      await tester.tap(find.text(dayLabel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Select end date'), findsOneWidget);
      await tester.tap(find.text(dayLabel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final expectedDate = formatRegionalDate(
        todayAtTen,
        const Locale('en', 'GB'),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('$expectedDate – $expectedDate'),
        ),
        findsOneWidget,
      );
      // The active date also shows as a chip with a cross under the search.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-active-date')),
          matching: find.text('$expectedDate – $expectedDate'),
        ),
        findsOneWidget,
      );
      expect(find.byType(Card), findsNWidgets(3));
      expect(
        tester.widget<IconButton>(filterButton).tooltip,
        '1 active filter',
      );

      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(Card),
        findsNWidgets(4),
        reason: 'clearing the filters keeps the archived brews shown',
      );
      expect(find.text('Any rating'), findsOneWidget);
      expect(find.text('Any bean'), findsOneWidget);
      expect(
        find.text('Filter by bean, method, date, or rating'),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(filterButton).tooltip, 'Filters');

      await tester.ensureVisible(
        find.byKey(const ValueKey('history-rating-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-rating-filter')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('8.5+'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('8.5+').last);
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Alpha Bean'), findsOneWidget);
      expect(find.text('Beta Bean'), findsNothing);

      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Any bean'), findsOneWidget);
      expect(find.text('Any method'), findsOneWidget);
      expect(find.text('Any rating'), findsOneWidget);
      expect(
        find.text('Filter by bean, method, date, or rating'),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('history-bean-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-bean-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha Bean').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('history-method-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-method-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('V60').last);
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      await tester.ensureVisible(
        find.byKey(const ValueKey('history-rating-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-rating-filter')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('8.5+'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('8.5+').last);
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      // The card, the sheet's bean choice and the active-filter chip.
      expect(find.text('Alpha Bean'), findsNWidgets(3));
      expect(find.text('Beta Bean'), findsNothing);

      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('history-filter-sheet')),
          matching: find.text('Clear filters'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Filter by bean, method, date, or rating'),
        findsOneWidget,
      );
      expect(find.text('Any bean'), findsOneWidget);
      expect(find.text('Any method'), findsOneWidget);
      expect(find.text('Any rating'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('Beans sort by name, recent brew, and known roast date', (
    tester,
  ) async {
    final database = memoryDatabase();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(database.close);

    final repository = JournalRepository(database);
    final today = DateTime.now();
    final alphaId = await repository.createCoffee(
      name: 'Alpha Bean',
      roaster: 'Test roaster',
      roastDate: '2026-09-01',
    );
    final betaId = await repository.createCoffee(
      name: 'Beta Bean',
      roaster: 'Test roaster',
      roastDate: '2026-09-20',
    );
    await repository.createCoffee(name: 'Gamma Bean', roaster: 'Test roaster');
    final deltaId = await repository.createCoffee(
      name: 'Delta Bean',
      roaster: 'Test roaster',
    );
    await repository.setCoffeeArchived(deltaId, archived: true);
    await repository.createBrew(
      coffeeId: alphaId,
      methodName: 'V60',
      brewedAt: today.subtract(const Duration(days: 4)),
    );
    await repository.createBrew(
      coffeeId: betaId,
      methodName: 'Espresso',
      brewedAt: today.subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await _openBeans(tester);

    expect(_visibleBeanNames(tester), [
      'Alpha Bean',
      'Beta Bean',
      'Gamma Bean',
    ]);
    expect(find.text('Show archived'), findsNothing);

    final sortButton = find.byKey(const ValueKey('bean-sort'));
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    final sortItems = find.byType(CheckedPopupMenuItem<int>);
    expect(sortItems, findsNWidgets(7));
    expect(
      tester.widget<CheckedPopupMenuItem<int>>(sortItems.at(0)).checked,
      isTrue,
    );
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Most recently brewed'),
    );
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), [
      'Beta Bean',
      'Alpha Bean',
      'Gamma Bean',
    ]);
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Ascending'),
    );
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), [
      'Alpha Bean',
      'Beta Bean',
      'Gamma Bean',
    ]);
    // Undated beans remain last in both directions.
    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Descending'),
    );
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), [
      'Beta Bean',
      'Alpha Bean',
      'Gamma Bean',
    ]);

    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckedPopupMenuItem<int>>(sortItems.at(1)).checked,
      isTrue,
    );
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'Roast date'),
    );
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), [
      'Beta Bean',
      'Alpha Bean',
      'Gamma Bean',
    ]);

    await tester.tap(sortButton);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckedPopupMenuItem<int>>(sortItems.at(2)).checked,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), isNot(contains('Delta Bean')));
    await tester.ensureVisible(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    expect(_visibleBeanNames(tester), ['Delta Bean']);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'method navigation resets incompatible filters but not preferences',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = JournalRepository(database);
      final alphaId = await repository.createCoffee(
        name: 'Alpha Bean',
        roaster: 'Test roaster',
      );
      final betaId = await repository.createCoffee(
        name: 'Beta Bean',
        roaster: 'Test roaster',
      );
      final v60Id = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      await repository.createMethod(name: 'Espresso', category: 'espresso');
      for (final (coffee, method, rating, archived) in [
        (alphaId, 'V60', 8.5, false),
        (betaId, 'V60', 7.5, false),
        (alphaId, 'V60', 6.5, true),
        (alphaId, 'Espresso', 7.5, false),
      ]) {
        final id = await repository.createBrew(
          coffeeId: coffee,
          methodId: method == 'V60' ? v60Id : null,
          methodName: method,
          rating: rating,
        );
        if (archived) await repository.setBrewArchived(id, archived: true);
      }
      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _openHistory(tester);
      await tester.enterText(find.byType(TextField).first, 'no matches');
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
      await tester.tap(find.byKey(const ValueKey('history-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-bean-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta Bean').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);

      final navigation = find.byType(NavigationBar);
      final bounds = tester.getRect(navigation);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * 3.5 / 4, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      final seeBrews = find.byKey(ValueKey('method-brews-$v60Id'));
      await tester.ensureVisible(seeBrews);
      await tester.tap(seeBrews);
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(3));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('history-show-archived')),
            )
            .isSelected,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('history-filter-button')),
            )
            .tooltip,
        '1 active filter',
      );
      final options = await ListOptionsSettings(database).load();
      expect(options.showArchivedBrews, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}

Future<void> _openHistory(WidgetTester tester) async {
  final navigation = find.byType(NavigationBar);
  final bounds = tester.getRect(navigation);
  await tester.tapAt(
    Offset(bounds.left + bounds.width * 2.5 / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}

Future<void> _openBeans(WidgetTester tester) async {
  final navigation = find.byType(NavigationBar);
  final bounds = tester.getRect(navigation);
  await tester.tapAt(
    Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}

List<String> _visibleBeanNames(WidgetTester tester) =>
    tester.widgetList<Card>(find.byType(Card)).map((card) {
      final title = find.descendant(
        of: find.byWidget(card),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(title.first).data!;
    }).toList();
