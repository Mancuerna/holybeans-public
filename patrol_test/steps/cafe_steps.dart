import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/cafes/cafe_drink_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

Future<void> checkCafeJournal(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final home = JournalRepository(database);
  await home.createCoffee(
    name: 'Home bag',
    roaster: 'Ineffable',
    initialGrams: 250,
  );
  final before = await home.allCoffees();
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(find.byKey(const ValueKey('cafes-button')));
  await $.tap(find.byKey(const ValueKey('cafe-add')));
  final scroll = find
      .descendant(
        of: find.byType(CafeDrinkForm),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> fill(String key, String value) async {
    final field = find.byKey(ValueKey('cafe-$key'));
    await $.tester.scrollUntilVisible(field, 260, scrollable: scroll);
    await $.tester.enterText(field, value);
    await $.pumpAndSettle();
  }

  await $.tap(find.text('Find a café'));
  await $.tester.enterText(find.byType(TextField), 'Hola Coffee Lagasca');
  await $.pumpAndSettle();
  await $.tap(find.text('Hola Coffee Lagasca').last);
  expect(
    $.tester
        .widget<TextFormField>(find.byKey(const ValueKey('cafe-city')))
        .controller!
        .text,
    'Madrid',
  );
  expect(
    $.tester
        .widget<TextFormField>(find.byKey(const ValueKey('cafe-country')))
        .controller!
        .text,
    'España',
  );
  await fill('type', 'V60');
  await fill('roaster', 'ine');
  await $.tap(find.text('Ineffable').last);
  await fill('origin', 'bra');
  await $.tap(find.byKey(const ValueKey('country-option-BR')));
  expect(find.text('💀  '), findsOneWidget);
  await fill('origin', 'ken');
  await $.tap(find.byKey(const ValueKey('country-option-KE')));
  await fill('process', 'Lavado');
  await fill('rating', '8');
  await fill('price', '4,50');
  await fill('notes', 'Café de prueba aislado');
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  final save = find.byKey(const ValueKey('cafe-save'));
  await $.tester.scrollUntilVisible(save, 200, scrollable: scroll);
  await $.tap(save);
  expect((await CafeRepository(database).read()).drinks, hasLength(1));
  await $.takeNativeScreenshot('cafe-journal-history');
  await $.tap(find.byKey(const ValueKey('cafe-stats-tab')));
  await $.takeNativeScreenshot('cafe-journal-stats');
  await $.tap(find.byKey(const ValueKey('cafe-history-tab')));
  await $.tap(find.text('Hola Coffee Lagasca · V60'));
  await fill('venue', 'Discarded change');
  await $.platformAutomator.android.pressBack();
  await $.pumpAndSettle();
  await $.tap(find.byType(BackButton));
  expect(find.text('Discard changes?'), findsOneWidget);
  await $.tap(find.text('Discard'));
  expect(
    (await CafeRepository(database).read()).cafes.single.name,
    'Hola Coffee Lagasca',
  );
  expect(await home.allCoffees(), before);
  expect(await home.allBrews(), isEmpty);
}
