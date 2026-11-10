import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';

import 'helpers/test_database.dart';

/// A journal with one bean of 250 g and a 15 g brew of it; with
/// [archiveCoffee], the coffee (and so the brew) archived.
Future<(AppDatabase, String)> _journal(
  WidgetTester tester, {
  bool archiveCoffee = false,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final database = memoryDatabase();
  addTearDown(database.close);
  final repository = JournalRepository(database);
  final coffeeId = await repository.createCoffee(
    name: 'Kenya',
    roaster: 'R',
    initialGrams: 250,
  );
  final lotId = (await repository.coffeeLots(coffeeId)).single.id;
  final id = await repository.createBrew(
    coffeeId: coffeeId,
    lotId: lotId,
    methodName: 'V60',
    doseGrams: 15,
  );
  if (archiveCoffee) {
    await repository.setCoffeeArchived(coffeeId, archived: true);
  }
  await tester.pumpWidget(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  final bounds = tester.getRect(find.byType(NavigationBar));
  await tester.tapAt(
    Offset(bounds.left + bounds.width * 2.5 / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
  return (database, id);
}

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(ValueKey('brew-card-$id')),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('the brew menu deletes after confirming', (tester) async {
    final (_, id) = await _journal(tester);
    await _openMenu(tester, id);
    await tester.tap(find.byKey(ValueKey('brew-delete-$id')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Its 15 g go back to the coffee.'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('brew-card-$id')), findsOneWidget);

    await _openMenu(tester, id);
    await tester.tap(find.byKey(ValueKey('brew-delete-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-brew-confirm')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('brew-card-$id')), findsNothing);
    expect(find.text('Brew deleted'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a brew archived with its coffee offers no deletion', (
    tester,
  ) async {
    final (_, id) = await _journal(tester, archiveCoffee: true);
    await tester.tap(find.byKey(const ValueKey('history-show-archived')));
    await tester.pumpAndSettle();
    await _openMenu(tester, id);
    expect(find.text('Edit'), findsOneWidget, reason: 'the menu is open');
    expect(find.byKey(ValueKey('brew-delete-$id')), findsNothing);
    await _close(tester);
  });
}
