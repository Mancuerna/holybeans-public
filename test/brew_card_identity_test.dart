import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';

import 'helpers/test_database.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets('same-name coffees remain distinct in $language at 2x text', (
      tester,
    ) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = JournalRepository(db);
      final ids = <String>[];
      for (final process in ['Lavado', 'Anaeróbico', '']) {
        final coffee = await repository.createCoffee(
          name: 'Syoum Family',
          roaster: 'Tostador',
          process: process,
        );
        ids.add(
          await repository.createBrew(
            coffeeId: coffee,
            methodName: 'V60',
            doseGrams: 15,
            waterGrams: 250,
          ),
        );
      }
      final blend = await repository.createCoffeeWithComponents(
        name: 'Syoum Family',
        roaster: 'Tostador',
        components: const [
          CoffeeComponentInput(process: 'Lavado'),
          CoffeeComponentInput(process: 'Anaeróbico'),
          CoffeeComponentInput(process: 'Lavado'),
        ],
      );
      ids.add(await repository.createBrew(coffeeId: blend, methodName: 'V60'));
      await tester.pumpWidget(
        HolyBeansApp(database: db, initialLocale: Locale(language)),
      );
      await tester.pumpAndSettle();
      final nav = tester.getRect(find.byType(NavigationBar));
      await tester.tapAt(Offset(nav.left + nav.width * 2.5 / 4, nav.center.dy));
      await tester.pumpAndSettle();
      for (final (index, identity) in [
        'Lavado · Tostador',
        'Anaeróbico · Tostador',
        'Tostador',
        'Lavado / Anaeróbico · Tostador',
      ].indexed.toList().reversed) {
        final card = find.byKey(ValueKey('brew-card-${ids[index]}'));
        final label = find.descendant(of: card, matching: find.text(identity));
        await tester.scrollUntilVisible(
          label,
          180,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(label, findsOneWidget);
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(label).width, lessThanOrEqualTo(360));
      }
      expect(find.byKey(const ValueKey('brew-density-toggle')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }
}
