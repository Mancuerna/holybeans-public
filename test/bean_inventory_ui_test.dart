import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en_GB'));

  testWidgets('bean, brew and repeat use one bag and survive rebuilding', (
    tester,
  ) async {
    final database = memoryDatabase();
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Añadir grano'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del café'),
      'Kieni',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(TextFormField, 'Cantidad comprada (g)'),
      250,
      scrollable: verticalScrollable(find.byType(CoffeeForm)),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cantidad comprada (g)'),
      '250',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(
      (await database.select(database.coffees).get()).single.name,
      'Kieni',
    );

    await tester.tap(find.text('Preparar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir método'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del método'),
      'V60',
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Estilo',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtro por vertido').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();
    expect(find.text('Lote de inventario'), findsNothing);
    expect(find.text('Inventario 1, 250 g'), findsNothing);
    final doseField = find.widgetWithText(TextFormField, 'Dosis (g)');
    await tester.scrollUntilVisible(
      doseField,
      200,
      scrollable: verticalScrollable(find.byType(BrewForm)),
    );
    await tester.enterText(doseField, '18');
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();
    expect(
      (await database.select(database.brews).get()).single.lotId,
      isNotNull,
    );
    expect(
      (await database.select(database.coffeeLots).get()).single.remainingGrams,
      232,
    );

    await tapBottomDestination(tester, 2);
    await tester.tap(find.byTooltip('Acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repetir').last);
    await tester.pumpAndSettle();
    final repeatedMethodDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Elige un método',
    );
    expect(repeatedMethodDropdown, findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(repeatedMethodDropdown)
          .initialValue,
      (await database.select(database.brews).get()).single.methodId,
    );
    final repeatedDoseField = find.widgetWithText(TextFormField, 'Dosis (g)');
    await tester.scrollUntilVisible(
      repeatedDoseField,
      200,
      scrollable: verticalScrollable(find.byType(BrewForm)),
    );
    expect(
      tester.widget<TextFormField>(repeatedDoseField).controller!.text,
      '18',
    );
    final repeatedGrindSetting = find.widgetWithText(
      TextFormField,
      'Punto de molienda',
    );
    await tester.scrollUntilVisible(
      repeatedGrindSetting,
      200,
      scrollable: verticalScrollable(find.byType(BrewForm)),
    );
    expect(repeatedGrindSetting, findsOneWidget);
    final repeatGrinderDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Molino',
    );
    await tester.scrollUntilVisible(
      repeatGrinderDropdown,
      220,
      scrollable: verticalScrollable(find.byType(BrewForm)),
    );
    await tester.pumpAndSettle();
    await tester.tap(repeatGrinderDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premolido').last);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Punto de molienda'),
      findsNothing,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final brews = await database.select(database.brews).get();
    expect(brews, hasLength(2));
    final repeatedBrew = brews.last;
    expect(repeatedBrew.isPreGround, isTrue);
    expect(repeatedBrew.grinderId, isNull);
    expect(repeatedBrew.grinderName, isNull);
    expect(repeatedBrew.grindSetting, isNull);
    expect(
      (await database.select(database.coffeeLots).get()).single.remainingGrams,
      214,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kieni'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
    await database.close();
  });

  testWidgets(
    'bean details start a brew with that bean and show related brew history',
    (tester) async {
      final database = memoryDatabase();
      final repository = JournalRepository(database);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(database.close);

      final coffeeId = await repository.createCoffee(
        name: 'Bean-linked coffee',
        roaster: 'Test roaster',
        initialGrams: 250,
      );
      await repository.createMethod(name: 'V60', category: 'pourover');
      final olderBrewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        brewedAt: DateTime(2026, 9, 27, 9),
      );
      final newerBrewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        brewedAt: DateTime(2026, 9, 27, 16),
      );
      final archivedBrewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Espresso',
        brewedAt: DateTime(2026, 9, 28, 9),
      );
      await repository.setBrewArchived(archivedBrewId, archived: true);

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      await tester.tap(find.text('Bean-linked coffee'));
      await tester.pumpAndSettle();

      expect(find.text('Brew with this bean'), findsOneWidget);
      expect(find.text('Recent brews'), findsOneWidget);
      expect(
        find.byKey(ValueKey('bean-recent-brew-$olderBrewId')),
        findsOneWidget,
      );
      final olderBrewCard = find.byKey(
        ValueKey('bean-recent-brew-$olderBrewId'),
      );
      final newerBrewCard = find.byKey(
        ValueKey('bean-recent-brew-$newerBrewId'),
      );
      final olderBrewTile = tester.widget<ListTile>(
        find.descendant(of: olderBrewCard, matching: find.byType(ListTile)),
      );
      final newerBrewTile = tester.widget<ListTile>(
        find.descendant(of: newerBrewCard, matching: find.byType(ListTile)),
      );
      final deviceLocale = tester.binding.platformDispatcher.locale;
      final morningTimestamp = DateFormat.yMd(deviceLocale.toString())
          .add_jm()
          .format(DateTime(2026, 9, 27, 9));
      final afternoonTimestamp = DateFormat.yMd(deviceLocale.toString())
          .add_jm()
          .format(DateTime(2026, 9, 27, 16));
      expect((olderBrewTile.title as Text).data, 'V60');
      expect((newerBrewTile.title as Text).data, 'V60');
      expect((olderBrewTile.subtitle as Text).data, contains(morningTimestamp));
      expect(
        (newerBrewTile.subtitle as Text).data,
        contains(afternoonTimestamp),
      );
      final archivedBrewCard = find.byKey(
        ValueKey('bean-recent-brew-$archivedBrewId'),
      );
      await tester.scrollUntilVisible(
        archivedBrewCard,
        180,
        scrollable: verticalScrollable(find.byType(BottomSheet).last),
      );
      expect(
        find.descendant(
          of: archivedBrewCard,
          matching: find.textContaining('Archived'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: archivedBrewCard, matching: find.byType(ListTile)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('brew-detail-edit')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.textContaining('Espresso'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
      await tester.pumpAndSettle();
      final brewWithBeanButton = find.byKey(
        const ValueKey('brew-with-bean-button'),
      );
      await tester.ensureVisible(brewWithBeanButton);
      await tester.tap(brewWithBeanButton);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CoffeePicker>(find.byType(CoffeePicker)).value,
        coffeeId,
      );
      final formException = tester.takeException();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      expect(formException, isNull);
    },
  );

  testWidgets(
    'coffee archive dialog cancels cleanly and saves an optional rating',
    (tester) async {
      final database = memoryDatabase();
      final repository = JournalRepository(database);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(database.close);

      final coffeeId = await repository.createCoffee(
        name: 'Archive candidate',
        roaster: 'Test roaster',
        initialGrams: 100,
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 10,
      );

      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: database),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 1);
      await tester.tap(find.text('Archive candidate').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Archive bean'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('coffee-archive-dialog')),
        findsOneWidget,
      );
      expect(find.text('No rating'), findsOneWidget);
      expect(find.text('Slide to rate'), findsOneWidget);
      expect(find.byTooltip('Clear rating'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await database.select(database.coffees).getSingle()).archivedAtMs,
        isNull,
      );
      expect(
        (await database.select(database.brews).getSingle()).archivedAtMs,
        isNull,
      );
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        90,
      );

      await tester.tap(find.byTooltip('Archive bean'));
      await tester.pumpAndSettle();
      final ratingSlider = find.byType(Slider);
      expect(tester.widget<Slider>(ratingSlider).onChanged, isNotNull);
      final sliderBounds = tester.getRect(ratingSlider);
      await tester.tapAt(
        Offset(
          sliderBounds.left + 16 + (sliderBounds.width - 32) * 0.75,
          sliderBounds.center.dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(ratingSlider).value, 7.5);
      await tester.tap(find.text('Archive bean').last);
      await tester.pumpAndSettle();

      final archivedCoffee = await database
          .select(database.coffees)
          .getSingle();
      final archivedBrew = await database.select(database.brews).getSingle();
      expect(archivedCoffee.archivedAtMs, isNotNull);
      expect(archivedCoffee.rating, 7.5);
      expect(archivedBrew.archivedAtMs, isNotNull);
      expect(archivedBrew.archivedByCoffee, isTrue);
      expect(
        (await database.select(database.coffeeLots).getSingle()).remainingGrams,
        90,
      );

      await tester.ensureVisible(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive candidate').last);
      await tester.pumpAndSettle();
      expect(find.text('7.5 / 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('saved overdraft asks to archive only after the brew is stored', (
    tester,
  ) async {
    final database = memoryDatabase();
    final repository = JournalRepository(database);
    addTearDown(database.close);
    await repository.createCoffee(
      name: 'Low stock coffee',
      roaster: 'Test roaster',
      initialGrams: 10,
    );
    await repository.createMethod(name: 'V60');

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> saveOversizedDose() async {
      await tester.tap(find.text('Brew').last);
      await tester.pumpAndSettle();
      final methodDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Choose a method',
      );
      await tester.tap(methodDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('V60').last);
      await tester.pumpAndSettle();
      final formScrollable = find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first;
      final doseField = find.widgetWithText(TextFormField, 'Dose (g)');
      await tester.scrollUntilVisible(
        doseField,
        220,
        scrollable: formScrollable,
      );
      await tester.enterText(doseField, '15');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
    }

    await saveOversizedDose();
    expect(find.byKey(const ValueKey('coffee-archive-dialog')), findsOneWidget);
    expect((await database.select(database.brews).get()).length, 1);
    expect(
      (await database.select(database.coffees).getSingle()).archivedAtMs,
      isNull,
    );
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      0,
    );
    expect(
      (await database.select(database.coffeeLots).getSingle()).overdrawGrams,
      5,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await database.select(database.coffees).getSingle()).archivedAtMs,
      isNull,
    );
    expect(
      (await database.select(database.brews).getSingle()).archivedAtMs,
      isNull,
    );

    await saveOversizedDose();
    expect(find.byKey(const ValueKey('coffee-archive-dialog')), findsOneWidget);
    expect((await database.select(database.brews).get()).length, 2);
    await tester.tap(find.text('Archive bean').last);
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.coffees).getSingle()).archivedAtMs,
      isNotNull,
    );
    final brews = await database.select(database.brews).get();
    expect(brews, hasLength(2));
    expect(brews.every((brew) => brew.archivedByCoffee == true), isTrue);
    expect(brews.every((brew) => brew.archivedAtMs != null), isTrue);
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      0,
    );
    expect(
      (await database.select(database.coffeeLots).getSingle()).overdrawGrams,
      20,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
