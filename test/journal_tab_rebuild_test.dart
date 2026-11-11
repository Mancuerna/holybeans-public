import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/core/journal_search_toolbar.dart';
import 'package:holybeans/ui/home/home_tab.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  testWidgets('tab switches retain hidden tabs, search and current data', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repository = JournalRepository(db);
    final coffee = await repository.createCoffee(
      name: 'Fixture',
      roaster: 'Test',
      initialGrams: 250,
    );
    await repository.createBrew(
      coffeeId: coffee,
      lotId: (await repository.coffeeLots(coffee)).single.id,
      methodName: 'V60',
      doseGrams: 18,
    );
    await tester.pumpWidget(
      HolyBeansApp(database: db, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    JournalSearchToolbar search() => tester.widget(
      find.descendant(
        of: find.byType(BeansTab),
        matching: find.byType(JournalSearchToolbar),
      ),
    );
    search().controller.text = 'Fixture';
    await tester.pumpAndSettle();
    for (final tab in [2, 3, 2]) {
      await tapBottomDestination(tester, tab);
    }
    final home = find.byType(HomeTab, skipOffstage: false);
    final beans = find.byType(BeansTab, skipOffstage: false);
    final counts = await countWidgetRebuilds(
      {'home': tester.element(home), 'beans': tester.element(beans)},
      () async {
        for (var i = 0; i < 100; i++) {
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .onDestinationSelected!(i.isEven ? 3 : 2);
          await tester.pump();
        }
      },
    );
    stdout.writeln('JOURNAL_TAB_BUILDS ${jsonEncode(counts)}');
    expect(counts, {'home': 0, 'beans': 0});
    await tester.pumpAndSettle();
    final added = await repository.createCoffee(
      name: 'Fixture new',
      roaster: 'Test',
      initialGrams: 100,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<HomeTab>(home).data.coffees.map((coffee) => coffee.id),
      contains(added),
    );
    expect(
      tester.widget<BeansTab>(beans).data.coffees.map((coffee) => coffee.id),
      contains(added),
    );
    await tapBottomDestination(tester, 1);
    expect(search().controller.text, 'Fixture');
    expect(find.text('Fixture new'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
