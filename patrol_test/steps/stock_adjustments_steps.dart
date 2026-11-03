import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

Future<void> checkStockAdjustments(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final repo = JournalRepository(db);
  final id = await repo.createCoffee(
    name: 'Stock test coffee',
    roaster: 'Patrol',
    initialGrams: 250,
  );
  final lot = (await repo.coffeeLots(id)).single.id;
  await repo.createBrew(
    coffeeId: id,
    lotId: lot,
    methodName: 'V60',
    doseGrams: 100,
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: db, initialLocale: const Locale('en')),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Beans'),
    ),
  );
  await $.tap(find.byKey(ValueKey('bean-card-$id')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('adjust-stock')),
  );
  await $.tap(find.byKey(const ValueKey('adjust-stock')));
  await $.enterText(find.byKey(const ValueKey('adjustment-grams')), '30');
  await $.enterText(
    find.byKey(const ValueKey('adjustment-notes')),
    'Sample for a friend',
    hideKeyboard: false,
  );
  await $.platform.android.pressBack();
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('save-adjustment')),
  );
  await $.tap(find.byKey(const ValueKey('save-adjustment')));
  await $.pumpAndSettle();
  expect(await repo.coffeeStockBalance(id), 120);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('stock-adjustment-history')),
  );
  await $.tap(find.byKey(const ValueKey('stock-adjustment-history')));
  await $.scrollUntilVisible(finder: find.text('Sample for a friend'));
  await $.takeNativeScreenshot('stock-adjustment-gift');
  await $.tap(find.text('Undo'));
  await $.tap(find.text('Cancel'));
  expect(await repo.coffeeStockBalance(id), 120);
  await $.tap(find.text('Undo'));
  await $.tap(find.widgetWithText(FilledButton, 'Undo'));
  await $.pumpAndSettle();
  expect(await repo.coffeeStockBalance(id), 150);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('adjust-stock')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('adjust-stock')));
  await $.tap(find.byKey(const ValueKey('adjustment-reason')));
  await $.tap(find.text('Weighed correction').last);
  await $.enterText(
    find.byKey(const ValueKey('adjustment-grams')),
    '42.5',
    hideKeyboard: false,
  );
  await $.platform.android.pressBack();
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('save-adjustment')),
  );
  await $.takeNativeScreenshot('stock-adjustment-correction');
  await $.tap(find.byKey(const ValueKey('save-adjustment')));
  await $.pumpAndSettle();
  expect(await repo.coffeeStockBalance(id), 42.5);
  final backup = await JournalBackup(db).exportJson();
  await JournalBackup(db).restoreJson(backup);
  expect((await repo.stockAdjustments(id)).length, 2);
  expect(await repo.coffeeStockBalance(id), 42.5);
}
