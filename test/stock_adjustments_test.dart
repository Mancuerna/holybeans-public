import 'dart:convert';

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
  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(
      name: 'Test',
      roaster: 'R',
      initialGrams: 250,
    );
    lot = (await repo.coffeeLots(coffee)).single.id;
  });
  tearDown(() => db.close());
  Future<CoffeeStock> stock() async => CoffeeStock(
    lots: await repo.coffeeLots(coffee),
    portions: await db.select(db.frozenPortions).get(),
    adjustments: await repo.stockAdjustments(coffee),
  );
  Future<String> adjust(String reason, double grams, {String? portion}) =>
      repo.adjustStock(
        coffeeId: coffee,
        reason: reason,
        grams: grams,
        frozenPortionId: portion,
      );
  for (final reason in ['gift', 'waste']) {
    test(
      'decimal frozen $reason empties the portion and undo restores it',
      () async {
        final id = await repo.freezeCoffee(
          lotId: lot,
          grams: 50.1,
          frozenDate: '2026-10-01',
        );
        final first = await adjust(reason, 20.2, portion: id);
        final last = await adjust(reason, 29.9, portion: id);
        var portion = await db.select(db.frozenPortions).getSingle();
        expect(portion.remainingGrams, 0);
        expect(portion.thawedAtMs, isNotNull);
        expect((await stock()).frozenGrams, 0);
        final adjustment = (await repo.stockAdjustments(coffee))
            .singleWhere((row) => row.operationId == last);
        expect(adjustment.resultingGrams, 0);

        await repo.undoStockAdjustment(last);
        portion = await db.select(db.frozenPortions).getSingle();
        expect(portion.remainingGrams, 29.9);
        expect(portion.thawedAtMs, isNull);
        await repo.undoStockAdjustment(first);
        portion = await db.select(db.frozenPortions).getSingle();
        expect(portion.remainingGrams, 50.1);
        expect(portion.thawedAtMs, isNull);
        expect((await repo.coffeeLot(lot))!.remainingGrams, 199.9);
        expect((await stock()).consumedGrams, 0);
      },
    );
  }

  test(
    'a frozen correction within zero tolerance empties the portion',
    () async {
      final id = await repo.freezeCoffee(
        lotId: lot,
        grams: 10,
        frozenDate: '2026-10-01',
      );
      await adjust('correction', 0.0000001, portion: id);
      final portion = await db.select(db.frozenPortions).getSingle();
      expect(portion.remainingGrams, 0);
      expect(portion.thawedAtMs, isNotNull);
      expect((await repo.stockAdjustments(coffee)).single.resultingGrams, 0);
    },
  );

  test('undoing a frozen refill marks the portion empty again', () async {
    final id = await repo.freezeCoffee(
      lotId: lot,
      grams: 10,
      frozenDate: '2026-10-01',
    );
    await adjust('gift', 10, portion: id);
    final refill = await adjust('correction', 5, portion: id);
    await repo.undoStockAdjustment(refill);
    final portion = await db.select(db.frozenPortions).getSingle();
    expect(portion.remainingGrams, 0);
    expect(portion.thawedAtMs, isNotNull);
  });

  test(
    'gifts, waste and corrections leave brewed grams and purchase unchanged',
    () async {
      final brew = await repo.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 100,
      );
      await adjust('gift', 30);
      final waste = await adjust('waste', 5);
      expect((await stock()).remainingGrams, 115);
      expect((await stock()).consumedGrams, 100);
      await adjust('correction', 120);
      expect((await stock()).consumedGrams, 100);
      await repo.undoStockAdjustment(waste);
      await repo.undoStockAdjustment(waste);
      expect((await stock()).remainingGrams, 125);
      expect((await stock()).consumedGrams, 100);
      await repo.deleteBrew(brew);
      expect((await stock()).remainingGrams, 225);
      expect((await stock()).consumedGrams, 0);
      expect((await repo.coffeeLot(lot))!.initialGrams, 250);
    },
  );
  test(
    'one total spans internal records and undo restores their balances',
    () async {
      await db
          .into(db.coffeeLots)
          .insert(
            CoffeeLot(
              id: 'other',
              coffeeId: coffee,
              initialGrams: 50,
              remainingGrams: 50,
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          );
      final id = await adjust('gift', 80);
      expect((await stock()).remainingGrams, 220);
      expect((await repo.stockAdjustments(coffee)).length, 2);
      expect((await stock()).consumedGrams, 0);
      await repo.undoStockAdjustment(id);
      expect((await repo.coffeeLot('other'))!.remainingGrams, 50);
      expect((await repo.coffeeLot(lot))!.remainingGrams, 250);
      await adjust('correction', 42);
      expect((await stock()).remainingGrams, 42);
      expect((await stock()).consumedGrams, 0);
    },
  );
  test(
    'unknown balance is measured explicitly and old consumption stays unknown',
    () async {
      final unknown = await repo.createCoffee(name: 'Unknown', roaster: 'R');
      await expectLater(
        repo.adjustStock(coffeeId: unknown, reason: 'gift', grams: 1),
        throwsA(isA<StockAdjustmentException>()),
      );
      final id = await repo.adjustStock(
        coffeeId: unknown,
        reason: 'correction',
        grams: 42,
      );
      expect(await repo.coffeeStockBalance(unknown), 42);
      expect(
        (await repo.stockAdjustments(unknown)).single.previousGrams,
        isNull,
      );
      await repo.undoStockAdjustment(id);
      expect(await repo.coffeeStockBalance(unknown), isNull);
    },
  );
  test(
    'measuring mixed known and unknown records keeps the total in history',
    () async {
      await db
          .into(db.coffeeLots)
          .insert(
            CoffeeLot(
              id: 'unknown',
              coffeeId: coffee,
              createdAtMs: DateTime.now().millisecondsSinceEpoch + 1000,
              updatedAtMs: 0,
            ),
          );
      final id = await adjust('correction', 250);
      final rows = await repo.stockAdjustments(coffee);
      expect(rows.fold<double>(0, (sum, r) => sum + r.resultingGrams), 250);
      expect((await stock()).remainingGrams, 250);
      expect((await stock()).consumedGrams, isNull);
      await repo.undoStockAdjustment(id);
      expect((await repo.coffeeLot(lot))!.remainingGrams, 250);
      expect((await repo.coffeeLot('unknown'))!.remainingGrams, isNull);
    },
  );

  test('invalid and excessive removals are atomic', () async {
    final before = jsonDecode(await JournalBackup(db).exportJson())['data'];
    for (final value in [-1.0, 0.0, 251.0, double.nan, double.infinity]) {
      await expectLater(
        adjust('gift', value),
        throwsA(isA<StockAdjustmentException>()),
      );
    }
    expect(jsonDecode(await JournalBackup(db).exportJson())['data'], before);
  });
  test(
    'frozen gift, thaw, undo and delete preserve total without brewed grams',
    () async {
      final p = await repo.freezeCoffee(
        lotId: lot,
        grams: 100,
        frozenDate: '2026-10-01',
      );
      final gift = await adjust('gift', 20, portion: p);
      expect((await stock()).frozenGrams, 80);
      expect((await stock()).remainingGrams, 150);
      expect((await stock()).consumedGrams, 0);
      await repo.thawCoffee(p, 80);
      await repo.undoStockAdjustment(gift);
      expect((await stock()).frozenGrams, 20);
      expect((await stock()).remainingGrams, 230);
      final waste = await adjust('waste', 10, portion: p);
      await repo.deleteFrozenPortion(p);
      await repo.undoStockAdjustment(waste);
      expect((await stock()).remainingGrams, 250);
      expect((await stock()).consumedGrams, 0);
    },
  );
  test('correction undo cannot remove coffee already used and frozen cannot exceed capacity', () async {
    await adjust('correction', 0);
    final id = await adjust('correction', 20);
    await repo.createBrew(
      coffeeId: coffee,
      lotId: lot,
      methodName: 'V60',
      doseGrams: 15,
    );
    await expectLater(
      repo.undoStockAdjustment(id),
      throwsA(isA<StockAdjustmentException>()),
    );
    expect((await stock()).remainingGrams, 5);
    final p = await repo.freezeCoffee(
      lotId: lot,
      grams: 5,
      frozenDate: '2026-10-01',
    );
    await expectLater(
      adjust('correction', 6, portion: p),
      throwsA(isA<StockAdjustmentException>()),
    );
  });
  test(
    'archive blocks changes and unarchive preserves adjustment history',
    () async {
      final id = await adjust('gift', 20);
      await repo.setCoffeeArchived(coffee, archived: true);
      await expectLater(
        adjust('waste', 1),
        throwsA(isA<StockAdjustmentException>()),
      );
      await expectLater(
        repo.undoStockAdjustment(id),
        throwsA(isA<StockAdjustmentException>()),
      );
      await repo.setCoffeeArchived(coffee, archived: false);
      expect((await stock()).remainingGrams, 230);
      expect((await stock()).consumedGrams, 0);
    },
  );
  test('backup round trip, reversals and malformed adjustments', () async {
    final id = await adjust('gift', 20);
    await adjust('waste', 5);
    await repo.undoStockAdjustment(id);
    final backup = await JournalBackup(db).exportJson();
    await JournalBackup(db).restoreJson(backup);
    expect(
      jsonDecode(await JournalBackup(db).exportJson())['data'],
      jsonDecode(backup)['data'],
    );
    final invalid = jsonDecode(backup) as Map<String, dynamic>;
    invalid['data']['stockAdjustments'][0]['lotId'] = 'missing';
    await expectLater(
      JournalBackup(db).restoreJson(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect((await stock()).remainingGrams, 245);
    await repo.deleteUnusedCoffee(coffee);
    expect(await db.select(db.stockAdjustments).get(), isEmpty);
  });

  test(
    'profile measurements join the ledger and preserve brew consumption',
    () async {
      await repo.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 100,
      );
      await adjust('gift', 30);
      await repo.updateCoffeeProfile(
        id: coffee,
        name: 'Test',
        roaster: 'R',
        paidPriceCents: 2000,
        inventoryLotId: lot,
        initialGrams: 250,
        remainingGrams: 115,
        updateRemainingStock: true,
      );
      expect((await stock()).remainingGrams, 115);
      expect((await stock()).consumedGrams, 100);
      final correction = (await repo.stockAdjustments(coffee))
          .firstWhere((r) => r.reason == 'correction');
      await repo.undoStockAdjustment(correction.operationId);
      expect((await stock()).remainingGrams, 120);
      expect((await repo.coffee(coffee))!.paidPriceCents, 2000);
    },
  );
  test(
    'legacy backups omit the new ledger without losing their balances',
    () async {
      await adjust('gift', 20);
      final legacy = jsonDecode(
        await JournalBackup(db).exportJson(),
      ) as Map<String, dynamic>;
      legacy['version'] = 28;
      legacy['data'].remove('stockAdjustments');
      await JournalBackup(db).restoreJson(jsonEncode(legacy));
      expect((await stock()).remainingGrams, 230);
      expect(await repo.stockAdjustments(coffee), isEmpty);
      legacy['version'] = 29;
      await expectLater(
        JournalBackup(db).restoreJson(jsonEncode(legacy)),
        throwsFormatException,
      );
      expect((await stock()).remainingGrams, 230);
    },
  );
  test('concurrent removals cannot spend the same grams twice', () async {
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        adjust(
          'gift',
          200,
        ).then<Object>((id) => id).catchError((Object e) => e),
    ]);
    expect(results.whereType<String>().length, 1);
    expect(results.whereType<StockAdjustmentException>().length, 1);
    expect((await stock()).remainingGrams, 50);
  });
  test(
    'overdraw correction can be undone without changing previous consumption',
    () async {
      await repo.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: 260,
      );
      final id = await adjust('correction', 5);
      expect((await stock()).consumedGrams, 260);
      await repo.undoStockAdjustment(id);
      expect((await stock()).signedRemainingGrams, -10);
      expect((await stock()).consumedGrams, 260);
    },
  );
}
