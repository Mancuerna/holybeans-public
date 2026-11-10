import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/freshness_calendar.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/beans/freshness_calendar_page.dart';
import 'package:holybeans/ui/beans/roaster_group_header.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'roaster view persists, filters and keeps tab stock separate ($language)',
      (tester) async {
        final db = memoryDatabase();
        addTearDown(db.close);
        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = JournalRepository(db);
        final settings = ListOptionsSettings(db);
        await settings.save(const ListOptions(beansCompact: true));
        final mixed = await repo.createCoffee(
          name: 'Alpha',
          roaster: 'Big Sur',
          initialGrams: 250,
          roastDate: '2026-10-20',
        );
        final lotId = (await repo.coffeeLots(mixed)).single.id;
        await repo.freezeCoffee(
          lotId: lotId,
          grams: 100,
          frozenDate: '2026-10-25',
        );
        await repo.createCoffee(
          name: 'Beta',
          roaster: ' BIG   SUR ',
          initialGrams: 200,
        );
        final archived = await repo.createCoffee(
          name: 'Old',
          roaster: 'Archive',
          initialGrams: 500,
        );
        await repo.setCoffeeArchived(archived, archived: true);
        await repo.createCoffee(
          name: 'Other',
          roaster: 'North',
          initialGrams: 100,
        );
        Future<void> open() async {
          await tester.pumpWidget(
            HolyBeansApp(database: db, initialLocale: Locale(language)),
          );
          await tester.pumpAndSettle();
          await tapBottomDestination(tester, 1);
        }

        await open();
        await tester.tap(find.byKey(const ValueKey('beans-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('beans-view-roasters')));
        await tester.pumpAndSettle();
        expect((await settings.load()).beansByRoaster, isTrue);
        expect(find.byType(BeanCard), findsNothing);
        final header = tester
            .widgetList<RoasterGroupHeader>(find.byType(RoasterGroupHeader))
            .first;
        expect(header.group.beans, hasLength(2));
        expect(header.group.knownGrams, 350);
        await tester.tap(find.byKey(const ValueKey('roaster-group-big sur')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<BeanCard>(find.byType(BeanCard))
              .map((c) => c.coffee.name),
          ['Alpha', 'Beta'],
        );
        await tester.tap(find.byKey(const ValueKey('roaster-group-big sur')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Beta');
        await tester.pumpAndSettle();
        expect(
          tester.widget<BeanCard>(find.byType(BeanCard)).coffee.name,
          'Beta',
        );
        expect(find.byKey(const ValueKey('roaster-group-north')), findsNothing);
        await tester.enterText(find.byType(TextField).first, '');
        tester
            .widget<TabBar>(find.byKey(const ValueKey('bean-tabs')))
            .controller!
            .animateTo(1);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RoasterGroupHeader>(find.byType(RoasterGroupHeader))
              .group
              .knownGrams,
          100,
        );
        tester
            .widget<TabBar>(find.byKey(const ValueKey('bean-tabs')))
            .controller!
            .animateTo(2);
        await tester.pumpAndSettle();
        final archive = tester.widget<RoasterGroupHeader>(
          find.byType(RoasterGroupHeader),
        );
        expect(archive.group.beans.single.id, archived);
        expect(archive.showStock, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await open();
        await tester.tap(find.byKey(const ValueKey('beans-view-menu')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckedPopupMenuItem<int>>(
                find.byKey(const ValueKey('beans-view-roasters')),
              )
              .checked,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('beans-view-coffees')));
        await tester.pumpAndSettle();
        expect(find.byType(RoasterGroupHeader), findsNothing);
        expect((await settings.load()).beansByRoaster, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('calendar navigates months and updates from the live journal', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = JournalRepository(db);
    final today = DateTime.now();
    final roast = DateTime(
      today.year,
      today.month,
      today.day - 12,
    ).toIso8601String().substring(0, 10);
    final id = await repo.createCoffee(
      name: 'Calendar beans',
      roaster: 'R',
      initialGrams: 250,
      roastDate: roast,
    );
    await tester.pumpWidget(
      HolyBeansApp(database: db, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.byKey(const ValueKey('beans-calendar')));
    await tester.pumpAndSettle();
    expect(find.byType(FreshnessCalendarPage), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('calendar-previous')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-next')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('calendar-previous')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-style-espresso')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('calendar-style-espresso')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FreshnessCalendarPage>(find.byType(FreshnessCalendarPage))
          .lots
          .single
          .grams,
      250,
    );
    final lotId = (await repo.coffeeLots(id)).single.id;
    final entry = find.byKey(ValueKey('calendar-lot-$lotId'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeDetailsSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeDetailsSheet), findsNothing);
    await repo.setCoffeeArchived(id, archived: true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FreshnessCalendarPage>(find.byType(FreshnessCalendarPage))
          .lots,
      isEmpty,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('beans-calendar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final language in ['es', 'en']) {
    testWidgets('calendar fits narrow screens with large text ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(language),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: FreshnessCalendarPage(
            lots: List.generate(
              123,
              (i) => CalendarLot(
                id: '$i',
                coffeeId: 'c',
                coffeeName: 'Coffee with a long name',
                roaster: 'A long roaster name',
                grams: 100,
                roastDate: DateTime(2026, 10, 20),
              ),
            ),
            now: DateTime(2026, 11),
            onCoffee: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
