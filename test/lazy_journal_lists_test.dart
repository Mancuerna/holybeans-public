import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/history_tab.dart';
import 'package:holybeans/ui/core/page_layout.dart';
import 'package:holybeans/ui/core/swipe_actions.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('JournalListPage builds items on demand', (tester) async {
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: JournalListPage(
          header: const Text('Header'),
          itemCount: 100,
          itemBuilder: (context, index) {
            built.add(index);
            return SizedBox(height: 60, child: Text('Item $index'));
          },
        ),
      ),
    );
    expect(built, isNotEmpty);
    expect(built.length, lessThan(100));
    expect(built, isNot(contains(99)));

    await tester.scrollUntilVisible(
      find.text('Item 99'),
      500,
      scrollable: verticalScrollable(find.byType(JournalListPage)),
    );
    expect(built, contains(99));
    expect(find.text('Item 99'), findsOneWidget);
  });

  testWidgets('history mounts distant brews only when scrolled', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Lazy coffee',
      roaster: 'Test roaster',
    );
    for (var i = 0; i < 80; i++) {
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Method $i',
        doseGrams: 18,
        brewedAt: DateTime.now().subtract(Duration(days: i)),
      );
    }
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);

    expect(find.byType(BrewCard).evaluate().length, lessThan(80));
    expect(find.textContaining('Method 79'), findsNothing);
    expect(find.text('Today'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('Method 79'),
      500,
      scrollable: verticalScrollable(find.byType(HistoryTab)),
    );
    expect(find.textContaining('Method 79'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('archived beans mount distant cards only when scrolled', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    for (var i = 0; i < 80; i++) {
      final coffeeId = await repository.createCoffee(
        name: 'Bean $i',
        roaster: 'Test roaster',
      );
      await repository.setCoffeeArchived(coffeeId, archived: true);
    }
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    tester
        .widget<TabBar>(find.byKey(const ValueKey('bean-tabs')))
        .controller
        ?.animateTo(2);
    await tester.pumpAndSettle();

    expect(find.byType(BeanCard).evaluate().length, lessThan(80));
    expect(find.byType(SwipeActions).evaluate().length, lessThan(80));
    expect(find.text('Bean 0'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Bean 0'),
      500,
      scrollable: verticalScrollable(find.byType(BeansTab)),
    );
    expect(find.text('Bean 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
