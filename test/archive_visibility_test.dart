import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String coffee;
  late String lot;
  late String brew;
  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(
      name: 'Hachi',
      roaster: 'DAK',
      initialGrams: 30,
    );
    lot = (await repo.coffeeLots(coffee)).single.id;
    await repo.createBrew(
      coffeeId: coffee,
      lotId: lot,
      methodName: 'V60',
      doseGrams: 15.2,
    );
    brew = await repo.createBrew(
      coffeeId: coffee,
      lotId: lot,
      methodName: 'V60',
      doseGrams: 15,
    );
  });
  tearDown(() => db.close());
  Future<void> balance(double expected) async {
    final stock = CoffeeStock(
      lots: [(await repo.coffeeLot(lot))!],
      portions: [],
    );
    expect(stock.signedRemainingGrams, closeTo(expected, 1e-8));
  }

  Future<void> legacy() async {
    // Exact state produced by the former individual archive: dose returned.
    await (db.update(db.coffeeLots)..where((l) => l.id.equals(lot))).write(
      const CoffeeLotsCompanion(
        remainingGrams: Value(14.8),
        overdrawGrams: Value(0),
      ),
    );
    await (db.update(db.brews)..where((b) => b.id.equals(brew))).write(
      const BrewsCompanion(
        archivedAtMs: Value(1),
        archivedByCoffee: Value(false),
        stockReviewPending: Value(true),
      ),
    );
  }

  test(
    'archive/recover/repeat archive are neutral; edit and delete adjust once',
    () async {
      for (final archived in [true, true, false, false, true]) {
        await repo.setBrewArchived(brew, archived: archived);
        await balance(-0.2);
      }
      expect(
        CoffeeStock(
          lots: [(await repo.coffeeLot(lot))!],
          portions: [],
        ).consumedGrams,
        closeTo(30.2, 1e-8),
      );
      await repo.saveBrew(
        id: brew,
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 14,
      );
      await balance(0.8);
      await repo.deleteBrew(brew);
      await balance(14.8);
    },
  );
  test('coffee archive and recovery preserve independently archived brews and stock', () async {
    await repo.setBrewArchived(brew, archived: true);
    await repo.setCoffeeArchived(coffee, archived: true);
    await balance(-0.2);
    await repo.setCoffeeArchived(coffee, archived: false);
    await balance(-0.2);
    expect((await repo.brew(brew))!.archivedAtMs, isNotNull);
    expect((await repo.brew(brew))!.archivedByCoffee, false);
  });
  test('legacy is unchanged by recovery; deduction requires explicit review and is idempotent', () async {
    await legacy();
    await repo.setBrewArchived(brew, archived: false);
    await balance(14.8);
    await expectLater(
      repo.saveBrew(
        id: brew,
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 16,
      ),
      throwsA(isA<BrewStockReviewRequiredException>()),
    );
    await balance(14.8);
    await repo.resolveBrewStockReview(brew, deduct: true);
    await repo.resolveBrewStockReview(brew, deduct: true);
    await balance(-0.2);
    await repo.deleteBrew(brew);
    await balance(14.8);
  });
  test('legacy acknowledgement leaves manual balance; unreviewed deletion never returns twice', () async {
    await legacy();
    await repo.resolveBrewStockReview(brew, deduct: false);
    await balance(14.8);
    expect((await repo.brew(brew))!.stockReviewPending, false);
    await legacy();
    await repo.deleteBrew(brew);
    await balance(14.8);
  });
  test('v27 restore marks only old independent archives; v28 preserves unresolved recovered rows', () async {
    await repo.setBrewArchived(brew, archived: true);
    final backup = JournalBackup(db);
    final old = jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
    old['version'] = 27;
    for (final row in old['data']['brews'] as List) {
      row.remove('stockReviewPending');
    }
    await backup.restoreJson(jsonEncode(old));
    expect((await repo.brew(brew))!.stockReviewPending, true);
    await balance(-0.2); // Import never infers or repairs inventory.
    await repo.setBrewArchived(brew, archived: false);
    final current = await backup.exportJson();
    await backup.restoreJson(current);
    expect((await repo.brew(brew))!.stockReviewPending, true);
    await balance(-0.2);
  });
}
