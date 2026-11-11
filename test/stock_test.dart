import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/main.dart';

import 'helpers/test_database.dart';

void main() {
  test('typical dose is the median of the last five doses', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Doses',
      roaster: 'Roaster',
    );
    expect(typicalDose(coffeeId, const []), 15);
    final start = DateTime(2026, 9);
    for (final (day, dose) in [
      (0, 40.0),
      (1, 18.0),
      (2, 20.0),
      (3, 15.0),
      (4, 19.0),
      (5, 18.0),
    ]) {
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        doseGrams: dose,
        brewedAt: start.add(Duration(days: day)),
      );
    }
    final brews = await database.select(database.brews).get();
    // The 40 g brew is older than the last five.
    expect(typicalDose(coffeeId, brews), 18);
  });

  testWidgets('home warns about beans running low', (tester) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    Future<String> bean(String name, double grams) async {
      final id = await repository.createCoffeeWithComponents(
        name: name,
        roaster: 'Roaster',
        components: const [],
        initialGrams: grams,
      );
      final lotId = (await repository.coffeeLots(id)).single.id;
      await repository.createBrew(
        coffeeId: id,
        lotId: lotId,
        methodName: 'V60',
        doseGrams: 18,
      );
      return id;
    }

    final almostGone = await bean('Almost gone', 40);
    final plenty = await bean('Plenty', 250);
    final lotId = (await repository.coffeeLots(almostGone)).single.id;
    await repository.freezeCoffee(
      lotId: lotId,
      grams: 10,
      frozenDate: DateTime.now().toIso8601String().substring(0, 10),
    );

    final coffees = await database.select(database.coffees).get();
    final brews = await database.select(database.brews).get();
    final low = lowStock(
      coffees: coffees,
      brews: brews,
      freshGrams: {almostGone: 12, plenty: 232},
      frozenGrams: {almostGone: 10},
    );
    expect(low.single.coffee.id, almostGone);
    expect(low.single.doses, 0);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('home-low-stock'));
    expect(card, findsOneWidget);
    // 40 g − 18 g brewed − 10 g frozen = 12 g: less than one 18 g dose.
    expect(
      find.descendant(
        of: card,
        matching: find.text('Less than a dose left, 10 g in the freezer'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('12 g')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('low-stock-$plenty')), findsNothing);
    await tester.tap(find.byKey(ValueKey('low-stock-$almostGone')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
