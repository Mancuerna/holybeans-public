import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/main.dart';

void main() {
  test('brew cost follows the price per kilo of the whole purchase', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final priced = await repository.createCoffee(
      name: 'Priced',
      roaster: 'Roaster',
      initialGrams: 250,
      paidPriceCents: 1500,
    );
    final unpriced = await repository.createCoffee(
      name: 'Unpriced',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    for (final (coffeeId, dose) in [
      (priced, 18.0),
      (priced, 20.0),
      (priced, null),
      (unpriced, 18.0),
    ]) {
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        doseGrams: dose,
      );
    }
    final coffees = await database.select(database.coffees).get();
    final lots = await database.select(database.coffeeLots).get();
    final brews = await database.select(database.brews).get();
    final prices = pricePerKgByCoffee(coffees, lots);
    expect(prices, {priced: 60.0});
    final eighteen = brews.firstWhere(
      (brew) => brew.coffeeId == priced && brew.doseGrams == 18,
    );
    expect(brewCost(eighteen, prices), closeTo(1.08, 1e-9));

    final stats = BrewStats.compute(
      brews: brews,
      coffees: coffees,
      components: const [],
      styleOf: (_) => BrewStyle.filter,
      range: StatsRange.all,
      now: DateTime.now(),
      languageCode: 'en',
      pricePerKg: prices,
    );
    expect(stats.costedCount, 2);
    expect(stats.coffeeCost, closeTo(2.28, 1e-9));
    expect(stats.costPerCup, closeTo(1.14, 1e-9));
  });

  testWidgets('brew details show the cost of the coffee used', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Priced',
      roaster: 'Roaster',
      initialGrams: 250,
      paidPriceCents: 1500,
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
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
    await tester.tap(find.text('Priced'));
    await tester.pumpAndSettle();
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('€1.08'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
