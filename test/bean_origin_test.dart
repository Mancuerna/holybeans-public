import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';

void main() {
  test('free-text origins resolve to a country and flag', () {
    expect(coffeeCountryFor('Etiopía')?.code, 'ET');
    expect(coffeeCountryFor(' ethiopia ')?.code, 'ET');
    expect(coffeeCountryFor('Sumatra')?.code, 'ID');
    expect(coffeeCountryFor('Costa-Rica')?.code, 'CR');
    expect(coffeeCountryFor('Narnia'), isNull);
    expect(coffeeCountryFor('Kenya')!.flag, '🇰🇪');
    for (final name in ['España', 'Spain', 'espana', 'ES']) {
      final country = coffeeCountryFor(name)!;
      expect(country.code, 'ES');
      expect(country.flag, '🇪🇸');
      expect(country.nameFor('es'), 'España');
      expect(country.nameFor('en'), 'Spain');
    }
    expect(coffeeCountryFor('Brasil')!.flag, '💀', reason: 'easter egg');
    final codes = coffeeCountries.map((country) => country.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
  });

  testWidgets('bean cards show flags and farm details', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffeeWithComponents(
      name: 'Blend',
      roaster: 'Roaster',
      components: const [
        CoffeeComponentInput(
          country: 'Kenia',
          region: 'Nyeri',
          variety: 'SL28',
          process: 'Washed',
          altitudeMeters: 1850,
          producer: 'Gatomboya',
        ),
        CoffeeComponentInput(country: 'Brazil', process: 'Washed'),
      ],
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();

    final origin = tester.widget<Text>(
      find.byKey(ValueKey('bean-origin-$coffeeId')),
    );
    expect(
      origin.textSpan!.toPlainText(includeSemanticsLabels: false),
      '🇰🇪 💀  Kenia, Nyeri / Brazil',
    );
    expect(
      tester.widget<Text>(find.byKey(ValueKey('bean-farm-$coffeeId'))).data,
      'SL28, Washed, 1850 m, Gatomboya / Washed',
    );
    // Screen readers hear the country names, not "flag: Kenya".
    expect(find.bySemanticsLabel(RegExp('Flag|🇰🇪')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('the country field suggests countries with flags', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir grano').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Gesha español');
    final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
    await tester.ensureVisible(addOrigin);
    await tester.pumpAndSettle();
    await tester.tap(addOrigin);
    await tester.pumpAndSettle();
    final country = find.byKey(const ValueKey('origin-country'));
    await tester.ensureVisible(country);
    await tester.pumpAndSettle();
    await tester.enterText(country, 'espa');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-option-ES')));
    await tester.pumpAndSettle();
    expect(find.text('🇪🇸  '), findsOneWidget);
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();

    final coffee = await database.select(database.coffees).getSingle();
    final components = await JournalRepository(database)
        .coffeeComponents(coffee.id);
    expect(components.single.country, 'España');
    expect(find.byType(CoffeeForm), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('picking Brazil shows a skull and plays its sound', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('holybeans/device'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('holybeans/device'),
        null,
      ),
    );

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('es')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir grano').first);
    await tester.pumpAndSettle();
    final addOrigin = find.byKey(const ValueKey('add-coffee-origin'));
    await tester.ensureVisible(addOrigin);
    await tester.pumpAndSettle();
    await tester.tap(addOrigin);
    await tester.pumpAndSettle();
    final country = find.byKey(const ValueKey('origin-country'));
    await tester.ensureVisible(country);
    await tester.pumpAndSettle();

    await tester.enterText(country, 'bol');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('country-option-BO')));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('faaah')));

    await tester.enterText(country, 'bra');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('country-option-BR')),
        matching: find.text('💀'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('country-option-BR')));
    await tester.pumpAndSettle();
    expect(calls.where((method) => method == 'faaah'), hasLength(1));
    expect(find.text('💀  '), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
