import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('coffee draft survives resizing and saves from a short window', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFormSheet<Object>(
                context,
                CoffeeForm(repository: JournalRepository(db)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Coffee name');
    await tester.enterText(name, 'Fold test');
    for (final size in [const Size(800, 800), const Size(800, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(name).controller!.text, 'Fold test');
      expect(tester.takeException(), isNull);
    }

    tester.view.viewInsets = const FakeViewPadding(bottom: 215);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.scrollUntilVisible(
      save,
      100,
      scrollable: verticalScrollable(find.byType(CoffeeForm)),
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(CoffeeForm), findsNothing);
    expect((await db.select(db.coffees).get()).single.name, 'Fold test');
  });
}
