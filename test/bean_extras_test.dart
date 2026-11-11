import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets(
    'favourites rise to the top and cards show flavour notes and consumption',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = JournalRepository(database);
      await repository.createCoffee(name: 'Alpha', roaster: 'Test roaster');
      final zetaId = await repository.createCoffeeWithComponents(
        name: 'Zeta',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 250,
        flavorProfile: 'Nectarine, jasmine',
      );
      final lotId = (await repository.coffeeLots(zetaId)).single.id;
      await repository.createBrew(
        coffeeId: zetaId,
        lotId: lotId,
        methodName: 'V60',
        doseGrams: 18,
      );
      await repository.createBrew(
        coffeeId: zetaId,
        lotId: lotId,
        methodName: 'V60',
        doseGrams: 15,
      );

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(NavigationBar));
      await tester.tapAt(
        Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
      );
      await tester.pumpAndSettle();

      double top(String name) => tester.getRect(find.text(name).first).top;
      expect(top('Alpha'), lessThan(top('Zeta')));
      final zetaCard = find.byKey(ValueKey('bean-card-$zetaId'));
      expect(
        find.descendant(of: zetaCard, matching: find.text('nectarine')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: zetaCard, matching: find.text('2 brews, 33 g')),
        findsOneWidget,
      );
      expect(
        (await repository.coffee(zetaId))!.flavorProfile,
        'Nectarine, jasmine',
      );

      await tester.tap(find.text('Zeta'));
      await tester.pumpAndSettle();
      expect(find.text('Consumed'), findsOneWidget);
      await tester.tap(find.byTooltip('Mark as favourite'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      expect(top('Zeta'), lessThan(top('Alpha')));
      expect(
        find.descendant(
          of: find.byKey(ValueKey('bean-card-$zetaId')),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('bean-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bean-favorites-first')));
      await tester.pumpAndSettle();
      expect(top('Alpha'), lessThan(top('Zeta')));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('archiving offers the average brew rating as a start', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Averaged',
      roaster: 'Test roaster',
    );
    for (final rating in [7.0, 8.0, null]) {
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        rating: rating,
      );
    }

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Averaged'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive bean'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('archive-average-rating')))
          .data,
      'Your brews average 7.5 (2)',
    );
    await tester.tap(find.byKey(const ValueKey('archive-use-average')));
    await tester.pumpAndSettle();
    expect(find.text('Rating: 7.5 / 10'), findsOneWidget);
    await tester.tap(find.text('Archive bean').last);
    await tester.pumpAndSettle();
    expect((await database.select(database.coffees).getSingle()).rating, 7.5);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
