import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets('a method saved as percolation reads and edits as a pour over', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final id = await repository.createMethod(
      name: 'Old dripper',
      category: 'percolation',
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(Offset(bar.left + bar.width * 3.5 / 4, bar.center.dy));
    await tester.pumpAndSettle();

    final card = find.byKey(ValueKey('method-card-$id'));
    expect(
      find.descendant(of: card, matching: find.text('Pour-over')),
      findsOneWidget,
    );

    await tester.tap(find.text('Old dripper'));
    await tester.pumpAndSettle();
    final style = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Pour-over',
    );
    expect(style, findsOneWidget);
    await tester.tap(style);
    await tester.pumpAndSettle();
    expect(find.text('Percolation'), findsNothing);
    expect(find.text('Immersion'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
