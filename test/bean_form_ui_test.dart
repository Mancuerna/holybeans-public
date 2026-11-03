import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/ui_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en_GB'));

  testWidgets('bean editor changes remaining weight and roast level', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Edit weight coffee',
      roaster: 'Test roaster',
      initialGrams: 250,
      paidPriceCents: 1250,
    );
    final lot = await database.select(database.coffeeLots).getSingle();
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 18,
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.text('Edit weight coffee'));
    await tester.pumpAndSettle();
    expect(find.text('Adjust inventory'), findsNothing);
    await tester.tap(find.byTooltip('Edit bean'));
    await tester.pumpAndSettle();

    final dark = find.byKey(const ValueKey('roast-level-dark'));
    expect(dark, findsOneWidget);
    await tester.ensureVisible(dark);
    await tester.tap(dark);
    await tester.pumpAndSettle();

    final remainingField = find.widgetWithText(
      TextFormField,
      'Remaining quantity (g)',
    );
    final form = find.byType(CoffeeForm);
    final scrollable = verticalScrollable(form);
    await tester.scrollUntilVisible(
      remainingField,
      220,
      scrollable: scrollable,
    );
    await tester.enterText(remainingField, '190');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final coffee = await database.select(database.coffees).getSingle();
    final updatedLot = await database.select(database.coffeeLots).getSingle();
    expect(coffee.roastLevel, 'dark');
    expect(coffee.paidPriceCents, 1250);
    expect(updatedLot.initialGrams, 250);
    expect(updatedLot.remainingGrams, 190);
    expect(updatedLot.overdrawGrams, 0);
    expect(find.text('Adjust inventory'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'bean editor creates and edits an ordered blend on a narrow screen',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add bean'));
      await tester.pumpAndSettle();
      final form = find.byType(CoffeeForm);
      final scrollable = verticalScrollable(form);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Coffee name'),
        'Three origin blend',
      );

      final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
      for (var count = 0; count < 3; count++) {
        await tester.ensureVisible(addOrigin);
        await tester.pumpAndSettle();
        await tester.tap(addOrigin);
        await tester.pumpAndSettle();
      }

      final countryFields = find.widgetWithText(TextFormField, 'Country');
      await tester.scrollUntilVisible(
        countryFields.at(0),
        200,
        scrollable: scrollable,
      );
      await tester.enterText(countryFields.at(0), 'Kenya');
      await tester.scrollUntilVisible(
        countryFields.at(1),
        200,
        scrollable: scrollable,
      );
      await tester.enterText(countryFields.at(1), 'Brazil');

      final moveUp = find.byTooltip('Move origin up');
      await tester.ensureVisible(moveUp.first);
      await tester.pumpAndSettle();
      await tester.tap(moveUp.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final coffee = await database.select(database.coffees).getSingle();
      final createdComponents = await JournalRepository(database)
          .coffeeComponents(coffee.id);
      expect(createdComponents.map((component) => component.country), [
        'Brazil',
        'Kenya',
      ]);
      expect(createdComponents.map((component) => component.position), [0, 1]);
      final kenyaId = createdComponents.last.id;

      await tapBottomDestination(tester, 1);
      await tester.tap(find.text('Three origin blend'));
      await tester.pumpAndSettle();
      expect(find.text('Origin 1'), findsOneWidget);
      expect(find.text('Origin 2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Edit bean'));
      await tester.pumpAndSettle();
      final editor = find.byType(CoffeeForm);
      final editorScroll = verticalScrollable(editor);
      final regionFields = find.widgetWithText(TextFormField, 'Region');
      await tester.scrollUntilVisible(
        regionFields.at(1),
        220,
        scrollable: editorScroll,
      );
      await tester.enterText(regionFields.at(1), 'Nyeri');
      final editMoveUp = find.byTooltip('Move origin up');
      await tester.ensureVisible(editMoveUp.first);
      await tester.pumpAndSettle();
      await tester.tap(editMoveUp.first);
      await tester.pumpAndSettle();
      final removeOrigin = find.byTooltip('Remove origin');
      await tester.ensureVisible(removeOrigin.at(1));
      await tester.pumpAndSettle();
      await tester.tap(removeOrigin.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final editedComponents = await JournalRepository(database)
          .coffeeComponents(coffee.id);
      expect(editedComponents, hasLength(1));
      expect(editedComponents.single.id, kenyaId);
      expect(editedComponents.single.position, 0);
      expect(editedComponents.single.country, 'Kenya');
      expect(editedComponents.single.region, 'Nyeri');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('bean form shows origin fields with readable spacing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir grano'));
    await tester.pumpAndSettle();

    final name = find.widgetWithText(TextFormField, 'Nombre del café');
    final roaster = find.widgetWithText(TextFormField, 'Tostador');
    expect(
      tester.getRect(roaster).top - tester.getRect(name).bottom,
      greaterThanOrEqualTo(10),
    );
    expect(find.byType(ExpansionTile), findsNothing);
    final addOrigin = find.text('Añadir origen');
    expect(addOrigin, findsOneWidget);
    await tester.tap(addOrigin);
    await tester.pumpAndSettle();

    for (final label in [
      'País',
      'Región',
      'Variedad',
      'Proceso',
      'Finca',
      'Productor',
      'Altitud (m)',
    ]) {
      final field = find.widgetWithText(TextFormField, label);
      expect(field, findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
    }
    final country = find.widgetWithText(TextFormField, 'País');
    final region = find.widgetWithText(TextFormField, 'Región');
    expect(
      tester.getRect(region).top - tester.getRect(country).top,
      greaterThanOrEqualTo(48),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await database.close();
  });

  testWidgets('legacy bean without a lot can start inventory from its form', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Legacy bean',
      roaster: 'Local',
    );
    await database.delete(database.coffeeLots).go();
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beans').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Legacy bean').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit bean'));
    await tester.pumpAndSettle();

    expect(find.byType(CoffeeForm), findsOneWidget);
    final form = find.byType(CoffeeForm);
    final scrollable = verticalScrollable(form);
    final inventoryNote = find.textContaining('Older brews without a lot');
    await tester.scrollUntilVisible(inventoryNote, 240, scrollable: scrollable);
    expect(inventoryNote, findsOneWidget);
    final quantity = find.widgetWithText(
      TextFormField,
      'Purchased quantity (g)',
    );
    await tester.scrollUntilVisible(
      quantity,
      240,
      scrollable: verticalScrollable(find.byType(CoffeeForm)),
    );
    await tester.enterText(quantity, '250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final lot = await database.select(database.coffeeLots).getSingle();
    final brew = await database.select(database.brews).getSingle();
    expect(lot.initialGrams, 250);
    expect(lot.remainingGrams, 250);
    expect(brew.lotId, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await database.close();
  });

  testWidgets('bean details and edit form format saved quantity cleanly', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    await repository.createCoffee(
      name: 'Integral bean',
      roaster: 'Test roaster',
      initialGrams: 500,
      paidPriceCents: 1250,
    );
    await repository.createCoffee(
      name: 'Decimal bean',
      roaster: 'Test roaster',
      initialGrams: 12.75,
    );

    try {
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beans').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Integral bean').last);
      await tester.pumpAndSettle();
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('500 g'), findsOneWidget);
      expect(find.text('/ 500 g'), findsOneWidget);
      expect(find.text('Paid price'), findsOneWidget);
      expect(find.text('€12.50'), findsOneWidget);
      expect(find.text('Purchased quantity (g)'), findsNothing);
      expect(find.text('Paid price (€)'), findsNothing);

      await tester.tap(find.byTooltip('Edit bean'));
      await tester.pumpAndSettle();
      var quantity = find.widgetWithText(
        TextFormField,
        'Purchased quantity (g)',
      );
      await tester.scrollUntilVisible(
        quantity,
        240,
        scrollable: verticalScrollable(find.byType(CoffeeForm)),
      );
      expect(tester.widget<TextFormField>(quantity).controller!.text, '500');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Cancelling goes back to the bean's details; back closes them.
      expect(find.byTooltip('Edit bean'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decimal bean').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit bean'));
      await tester.pumpAndSettle();
      quantity = find.widgetWithText(TextFormField, 'Purchased quantity (g)');
      await tester.scrollUntilVisible(
        quantity,
        240,
        scrollable: verticalScrollable(find.byType(CoffeeForm)),
      );
      expect(tester.widget<TextFormField>(quantity).controller!.text, '12.75');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await database.close();
    }
  });

  testWidgets(
    'bean editor sets a fractional remaining weight on a narrow screen',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = JournalRepository(database);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(database.close);

      final coffeeId = await repository.createCoffee(
        name: 'Fractional bean',
        roaster: 'Test roaster',
        initialGrams: 30.75,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 18,
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      await tester.tap(find.text('Fractional bean').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit bean'));
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(
        TextFormField,
        'Remaining quantity (g)',
      );
      final editor = find.byType(CoffeeForm);
      final scrollable = verticalScrollable(editor);
      await tester.scrollUntilVisible(amountField, 220, scrollable: scrollable);
      expect(
        tester.widget<TextFormField>(amountField).controller!.text,
        '12.75',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.getRect(amountField).bottom, lessThan(520));
      await tester.enterText(amountField, '12.75');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        12.75,
      );
      await tester.tap(find.text('Fractional bean').last);
      await tester.pumpAndSettle();
      expect(find.text('12.8 g'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('multiple active inventory records do not offer adjustment', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    addTearDown(database.close);
    final coffeeId = await repository.createCoffee(
      name: 'Two lots',
      roaster: 'Test roaster',
      initialGrams: 250,
    );
    await database
        .into(database.coffeeLots)
        .insert(
          CoffeeLot(
            id: 'second-active-lot',
            coffeeId: coffeeId,
            initialGrams: 100,
            remainingGrams: 100,
            createdAtMs: 2,
            updatedAtMs: 2,
          ),
        );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 1);
    await tester.tap(find.text('Two lots').last);
    await tester.pumpAndSettle();
    expect(find.text('Remaining'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('350 g'),
      ),
      findsOneWidget,
    );
    expect(find.text('Inventory 1'), findsNothing);
    expect(find.text('Adjust inventory'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
