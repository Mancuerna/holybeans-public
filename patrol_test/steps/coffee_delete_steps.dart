import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

/// Checks deletion and protection of active and archived brew history.
Future<void> checkCoffeeDeletion(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final unused = await repository.createCoffee(
    name: 'Mistaken bean',
    roaster: 'Test',
    initialGrams: 250,
  );
  final active = await repository.createCoffee(
    name: 'Active history',
    roaster: 'Test',
  );
  final archived = await repository.createCoffee(
    name: 'Archived history',
    roaster: 'Test',
  );
  await repository.createBrew(coffeeId: active, methodName: 'V60');
  final brew = await repository.createBrew(
    coffeeId: archived,
    methodName: 'V60',
  );
  await repository.setBrewArchived(brew, archived: true);
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.byKey(const ValueKey('beans-view-menu')));
  await $.tap(find.byKey(const ValueKey('bean-density-toggle')));
  for (final id in [active, archived]) {
    await $.tap(find.byKey(ValueKey('bean-menu-$id')));
    expect(find.text('Delete coffee'), findsNothing);
    await $.tester.tapAt(const Offset(12, 240));
    await $.tester.pumpAndSettle();
  }
  await $.tap(find.byKey(ValueKey('bean-menu-$unused')));
  await $.tap(find.text('Delete coffee'));
  await $.takeNativeScreenshot('delete-unused-coffee-dialog');
  await $.tap(find.text('Cancel'));
  expect(await repository.coffee(unused), isNotNull);
  await $.tap(find.byKey(ValueKey('bean-menu-$unused')));
  await $.tap(find.text('Delete coffee'));
  await $.tap(find.byKey(const ValueKey('delete-bean-confirm')));
  await $.waitUntilVisible(find.text('Coffee deleted'));
  expect(await repository.coffee(unused), isNull);
  expect(await repository.allCoffees(), hasLength(2));
  expect(await repository.allBrews(), hasLength(2));
}
