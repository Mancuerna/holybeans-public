import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/main.dart';

void main() {
  test('saved list options read back, and odd values keep the defaults', () {
    const options = ListOptions(
      frozenBeanSort: BeanSort.roastDate,
      frozenBeansAscending: false,
      beanSort: BeanSort.roastDate,
      beansByRoaster: true,
      beansAscending: false,
      favoritesFirst: false,
      brewsCompact: true,
      showArchivedBrews: true,
      archivedBeansCompact: false,
    );
    final read = ListOptions.fromJson(options.toJson());
    expect(read.toJson(), options.toJson());
    // The Archived tab keeps its own order, newest brewed first by default.
    const archived = ListOptions(
      archivedBeanSort: BeanSort.name,
      archivedBeansAscending: true,
    );
    expect(ListOptions.fromJson(archived.toJson()).toJson(), archived.toJson());
    expect(
      (
        ListOptions.fromJson({'beanSort': 'roastDate'}).archivedBeanSort,
        ListOptions.fromJson({}).archivedBeansAscending,
      ),
      (BeanSort.recentBrew, false),
    );
    // Options saved before the archived density existed start compact there.
    expect(
      ListOptions.fromJson({'beansCompact': false}).archivedBeansCompact,
      isTrue,
    );

    expect(
      ListOptions.fromJson({'beanSort': 'freshness'}).frozenBeanSort,
      BeanSort.frozenDate,
    );
    expect(
      ListOptions.fromJson({'frozenBeanSort': 'freshness'}).frozenBeanSort,
      BeanSort.frozenDate,
    );
    expect(ListOptions.fromJson({}).frozenBeansAscending, isTrue);
    expect(ListOptions.fromJson({}).beansByRoaster, isFalse);
    expect(
      ListOptions.fromJson({'beansByRoaster': 'yes'}).beansByRoaster,
      isFalse,
    );
    expect(options.copyWith(beansCompact: true).beansByRoaster, isTrue);
    const defaults = ListOptions();
    expect(ListOptions.fromJson(null).toJson(), defaults.toJson());
    expect(ListOptions.fromJson('nonsense').toJson(), defaults.toJson());
    final odd = ListOptions.fromJson({
      'beanSort': 'byMood',
      'beansAscending': 'yes',
      'brewsAscending': true,
      'fromANewerApp': 1,
    });
    expect(
      (odd.beanSort, odd.beansAscending, odd.brewsAscending),
      (BeanSort.name, true, true),
    );
  });

  test('a journal without saved options, or with a broken value, starts '
      'from the defaults', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final settings = ListOptionsSettings(database);
    expect((await settings.load()).beanSort, BeanSort.name);
    await database
        .into(database.appPreferences)
        .insert(
          AppPreferencesCompanion.insert(
            id: const Value(1),
            shareFieldsJson: '[]',
            listOptionsJson: const Value('{not json'),
          ),
        );
    expect((await settings.load()).beanSort, BeanSort.name);
    await settings.save(const ListOptions(beanSort: BeanSort.recentBrew));
    expect((await settings.load()).beanSort, BeanSort.recentBrew);
  });

  testWidgets('the bean order and archived brews survive closing the app', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final alpha = await repository.createCoffee(
      name: 'Alpha Bean',
      roaster: 'R',
      roastDate: '2026-09-20',
    );
    await repository.createCoffee(
      name: 'Beta Bean',
      roaster: 'R',
      roastDate: '2026-09-01',
    );
    await repository.createBrew(coffeeId: alpha, methodName: 'V60');
    final archived = await repository.createBrew(
      coffeeId: alpha,
      methodName: 'V60',
    );
    await repository.setBrewArchived(archived, archived: true);

    Future<void> openApp() async {
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
    }

    await openApp();
    await _openTab(tester, 1);
    expect(_beanNames(tester), ['Alpha Bean', 'Beta Bean']);
    // Oldest roast first.
    for (final item in ['Roast date', 'Ascending']) {
      await tester.tap(find.byKey(const ValueKey('bean-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, item));
      await tester.pumpAndSettle();
    }
    expect(_beanNames(tester), ['Beta Bean', 'Alpha Bean']);
    await _openTab(tester, 2);
    expect(find.byType(Card), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-show-archived')));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));

    // Closed and opened again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await openApp();
    await _openTab(tester, 1);
    expect(_beanNames(tester), ['Beta Bean', 'Alpha Bean']);
    await _openTab(tester, 2);
    expect(find.byType(Card), findsNWidgets(2));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('history-show-archived')),
          )
          .tooltip,
      'Hide archived',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

Future<void> _openTab(WidgetTester tester, int index) async {
  final bounds = tester.getRect(find.byType(NavigationBar));
  await tester.tapAt(
    Offset(bounds.left + bounds.width * (index + 0.5) / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}

List<String> _beanNames(WidgetTester tester) =>
    tester.widgetList<Card>(find.byType(Card)).map((card) {
      final title = find.descendant(
        of: find.byWidget(card),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(title.first).data!;
    }).toList();
