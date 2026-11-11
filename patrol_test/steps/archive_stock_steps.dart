import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/stock_review_card.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

Future<void> checkArchiveStock(
  PatrolIntegrationTester $,
  AppDatabase db,
) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Archive consumption',
    roaster: 'Patrol',
    initialGrams: 30,
  );
  final lot = (await repo.coffeeLots(coffee)).single.id;
  await repo.createBrew(
    coffeeId: coffee,
    lotId: lot,
    methodName: 'V60',
    doseGrams: 15.2,
  );
  final id = await repo.createBrew(
    coffeeId: coffee,
    lotId: lot,
    methodName: 'V60',
    doseGrams: 15,
  );
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: db),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  final card = find.byKey(ValueKey('brew-card-$id'));
  Future<void> menu() =>
      $.tap(find.descendant(of: card, matching: find.byTooltip('Actions')));
  await menu();
  await $.tap(find.text('Archive brew'));
  expect((await repo.coffeeLot(lot))!.overdrawGrams, closeTo(0.2, 1e-8));
  await $.tap(find.byTooltip('Show archived'));
  await menu();
  await $.tap(find.text('Restore brew'));
  expect((await repo.coffeeLot(lot))!.overdrawGrams, closeTo(0.2, 1e-8));
  // Isolated old-version fixture: independent archive returned its 15 g.
  await (db.update(db.coffeeLots)..where((l) => l.id.equals(lot))).write(
    const CoffeeLotsCompanion(
      remainingGrams: Value(14.8),
      overdrawGrams: Value(0),
    ),
  );
  await (db.update(db.brews)..where((b) => b.id.equals(id))).write(
    const BrewsCompanion(
      stockReviewPending: Value(true),
      archivedAtMs: Value(1),
    ),
  );
  await $.pumpAndSettle();
  await $.tap(card);
  await $.waitUntilVisible(find.byType(StockReviewCard));
  await $.tap(find.byKey(const ValueKey('stock-review-deduct')));
  await $.tap(find.text('Cancel').last);
  expect((await repo.coffeeLot(lot))!.remainingGrams, 14.8);
  await $.tap(find.byKey(const ValueKey('stock-review-deduct')));
  await $.tap(find.text('Confirm consumption'));
  await $.pumpAndSettle();
  expect((await repo.brew(id))!.stockReviewPending, false);
  expect((await repo.coffeeLot(lot))!.overdrawGrams, closeTo(0.2, 1e-8));
  await $.takeNativeScreenshot('archive-stock-reviewed');
}
