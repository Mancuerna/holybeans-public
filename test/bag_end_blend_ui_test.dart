import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets('create a blend and archive selected sources together', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final a = await repository.createCoffee(
      name: 'Alpha',
      roaster: 'Test',
      initialGrams: 7,
    );
    final b = await repository.createCoffee(
      name: 'Beta',
      roaster: 'Test',
      initialGrams: 10,
    );
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(Offset(bar.left + bar.width * 1.5 / 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bean-add-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-blend')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Beta'));
    await tester.pumpAndSettle();
    final submit = find.text('Create blend · 17 g');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final keep = find.widgetWithText(CheckboxListTile, 'Beta');
    await tester.ensureVisible(keep);
    await tester.tap(keep);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive selected'));
    await tester.pumpAndSettle();
    expect((await repository.coffee(a))!.archivedAtMs, isNotNull);
    expect((await repository.coffee(b))!.archivedAtMs, isNull);
    await tester.tap(find.text('Bag ends').first);
    await tester.pumpAndSettle();
    expect(find.text('Mixed on'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Alpha'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
