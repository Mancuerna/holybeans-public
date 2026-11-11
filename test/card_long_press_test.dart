import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets('a long press on a unified brew card opens it to edit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
    );
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 2.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(ValueKey('brew-card-$brewId'));
    // Screen readers are told what holding it does.
    final node = tester.getSemantics(
      find.descendant(of: card, matching: find.text('Kenya')),
    );
    SemanticsNode? withHint = node;
    while (withHint != null &&
        withHint.hintOverrides?.onLongPressHint == null) {
      withHint = withHint.parent;
    }
    expect(withHint?.hintOverrides?.onLongPressHint, 'Edit');

    await tester.longPress(card);
    await tester.pumpAndSettle();
    expect(find.byType(BrewForm), findsOneWidget);
    expect(tester.widget<BrewForm>(find.byType(BrewForm)).existing?.id, brewId);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(BrewForm), findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a long press on a bean card opens it to edit, in both '
      'densities', (tester) async {
    final semantics = tester.ensureSemantics();
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coffeeId = await JournalRepository(database)
        .createCoffee(name: 'Kenya', roaster: 'R');
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(ValueKey('bean-card-$coffeeId'));
    for (final compact in [false, true]) {
      if (compact) {
        await tester.tap(find.byKey(const ValueKey('beans-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bean-density-toggle')));
        await tester.pumpAndSettle();
      }
      SemanticsNode? node = tester.getSemantics(
        find.descendant(of: card, matching: find.text('Kenya')),
      );
      while (node != null && node.hintOverrides?.onLongPressHint == null) {
        node = node.parent;
      }
      expect(node?.hintOverrides?.onLongPressHint, 'Edit bean');

      await tester.longPress(card);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CoffeeForm>(find.byType(CoffeeForm)).existing?.id,
        coffeeId,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.byType(CoffeeForm), findsNothing);
    }
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
