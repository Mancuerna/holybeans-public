import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'a bean can be frozen, found in the Frozen tab, thawed and brewed',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Freezer bean',
        roaster: 'Test roaster',
        initialGrams: 250,
      );
      final lotId = (await repository.coffeeLots(coffeeId)).single.id;
      await repository.createMethod(name: 'V60', category: 'pourover');

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      expect(find.text('Available (1)'), findsOneWidget);
      expect(find.text('Frozen (0)'), findsOneWidget);

      await tester.tap(find.text('Freezer bean'));
      await tester.pumpAndSettle();
      final freezeButton = find.byKey(const ValueKey('freeze-coffee-button'));
      await tester.ensureVisible(freezeButton);
      await tester.pumpAndSettle();
      await tester.tap(freezeButton);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('freeze-grams')), '300');
      await tester.tap(find.byKey(const ValueKey('freeze-save')));
      await tester.pumpAndSettle();
      expect(find.text('There is not that much unfrozen coffee.'), findsOne);

      await tester.enterText(find.byKey(const ValueKey('freeze-grams')), '100');
      await tester.tap(find.text('Tube'));
      await tester.pumpAndSettle();
      final save = tester
          .widget<FilledButton>(find.byKey(const ValueKey('freeze-save')))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();

      final portion = (await repository.frozenPortionsForLot(lotId)).single;
      expect(portion.container, 'tube');
      expect(find.text(portion.label), findsOneWidget);
      expect(find.text('100 / 100 g'), findsOneWidget);
      expect(find.textContaining('Write ${portion.label}'), findsOneWidget);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 150);
      expect(find.text('Frozen (1)'), findsOneWidget);

      final thaw = find.byKey(ValueKey('thaw-${portion.id}'));
      await tester.ensureVisible(thaw);
      await tester.pumpAndSettle();
      await tester.tap(thaw);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('thaw-grams')), '18');
      await tester.tap(find.byKey(const ValueKey('thaw-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('82 / 100 g'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 168);

      final thawAndBrew = find.byKey(ValueKey('thaw-brew-${portion.id}'));
      await tester.ensureVisible(thawAndBrew);
      await tester.pumpAndSettle();
      await tester.tap(thawAndBrew);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('thaw-grams')), '15');
      await tester.tap(find.byKey(const ValueKey('thaw-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(BrewForm), findsOneWidget);
      final dose = find.widgetWithText(TextFormField, 'Dose (g)');
      await tester.scrollUntilVisible(
        dose,
        240,
        scrollable: find
            .descendant(
              of: find.byType(BrewForm),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(dose).controller!.text, '15');
      expect(
        (await repository.frozenPortionsForLot(lotId)).single.remainingGrams,
        82,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('a new bean can be saved straight into the freezer', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final form = find.byType(CoffeeForm);
    final scrollable = find
        .descendant(of: form, matching: find.byType(Scrollable))
        .first;
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Coffee name'),
      'Straight to freezer',
    );
    final purchased = find.widgetWithText(
      TextFormField,
      'Purchased quantity (g)',
    );
    await tester.scrollUntilVisible(purchased, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.enterText(purchased, '250');
    // Closing the keyboard keeps the focused field from scrolling back.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('save-frozen-toggle'));
    await tester.scrollUntilVisible(toggle, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final grams = find.byKey(const ValueKey('create-freeze-grams'));
    await tester.scrollUntilVisible(grams, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(grams).controller!.text, '250');
    await tester.scrollUntilVisible(
      find.text('Vacuum bag'),
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacuum bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final coffee = await database.select(database.coffees).getSingle();
    final lot = await database.select(database.coffeeLots).getSingle();
    final portion = await database.select(database.frozenPortions).getSingle();
    expect(coffee.name, 'Straight to freezer');
    expect(lot.remainingGrams, 0);
    expect(portion.initialGrams, 250);
    expect(portion.container, 'vacuum_bag');
    expect(find.textContaining('Write ${portion.label}'), findsOneWidget);
    expect(find.text('Available (0)'), findsOneWidget);
    expect(find.text('Frozen (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('frozen coffee shows the age at which freezing paused it', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    await repository.createCoffeeWithComponents(
      name: 'Paused bean',
      roaster: 'Test roaster',
      components: const [],
      roastDate: '2026-09-20',
      initialGrams: 250,
      freeze: const FreezeRequest(grams: 250, frozenDate: '2026-09-24'),
    );

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.text('Frozen (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Frozen 4 days after roasting'), findsOneWidget);
    expect(find.textContaining('Roasted'), findsNothing);

    await tester.tap(find.text('Paused bean'));
    await tester.pumpAndSettle();
    final portion = await database.select(database.frozenPortions).getSingle();
    final age = find.byKey(ValueKey('frozen-age-${portion.id}'));
    await tester.ensureVisible(age);
    expect(tester.widget<Text>(age).data, 'Frozen 4 days after roasting');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'brewing frozen coffee leaves its portion unchanged until saving',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'All frozen',
        roaster: 'Test roaster',
        components: const [],
        initialGrams: 100,
        freeze: const FreezeRequest(grams: 60, frozenDate: '2026-09-02'),
      );
      final lotId = (await repository.coffeeLots(coffeeId)).single.id;
      final newer = await repository.freezeCoffee(
        lotId: lotId,
        grams: 40,
        frozenDate: '2026-09-20',
      );
      await repository.createMethod(name: 'V60', category: 'pourover');

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      await tester.tap(find.text('Frozen (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All frozen'));
      await tester.pumpAndSettle();
      final brew = find.byKey(const ValueKey('brew-with-bean-button'));
      await tester.ensureVisible(brew);
      await tester.pumpAndSettle();
      await tester.tap(brew);
      await tester.pumpAndSettle();

      // Two portions: the oldest is offered first, the other can be picked.
      expect(find.byKey(const ValueKey('choose-portion')), findsOneWidget);
      final options = tester
          .widgetList<SimpleDialogOption>(find.byType(SimpleDialogOption))
          .map((option) => (option.key! as ValueKey<String>).value)
          .toList();
      expect(options.last, 'choose-portion-$newer');
      await tester.tap(find.byKey(ValueKey('choose-portion-$newer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thaw-note')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('thaw-grams')), '18');
      await tester.tap(find.byKey(const ValueKey('thaw-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(BrewForm), findsOneWidget);
      final portions = await repository.frozenPortionsForLot(lotId);
      expect(
        portions.singleWhere((portion) => portion.id == newer).remainingGrams,
        40,
      );
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 0);
      expect(find.byKey(const ValueKey('brew-thaw-on-save')), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        (await repository.frozenPortionsForLot(lotId))
            .singleWhere((portion) => portion.id == newer)
            .remainingGrams,
        40,
      );
      expect((await repository.coffeeLot(lotId))!.remainingGrams, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('used-up portions are not offered in coffee details', (
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
      name: 'Mixed freezer',
      roaster: 'Test roaster',
      initialGrams: 100,
    );
    final lotId = (await repository.coffeeLots(coffeeId)).single.id;
    final active = await repository.freezeCoffee(
      lotId: lotId,
      grams: 25,
      frozenDate: '2026-10-01',
    );
    final exhausted = await repository.freezeCoffee(
      lotId: lotId,
      grams: 25,
      frozenDate: '2026-10-02',
    );
    await repository.thawCoffee(exhausted, 25);

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.text('Mixed freezer'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('frozen-portion-$active')), findsOneWidget);
    expect(find.byKey(ValueKey('frozen-portion-$exhausted')), findsNothing);
    expect(
      find.byKey(const ValueKey('toggle-thawed-actions.portions')),
      findsNothing,
    );
    final stored = await repository.frozenPortionsForLot(lotId);
    expect(stored.singleWhere((p) => p.id == exhausted).remainingGrams, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
