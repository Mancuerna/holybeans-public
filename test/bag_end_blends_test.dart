import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/test_database.dart';

void main() {
  test(
    'moves stock once, preserves source lots and archives only empty coffees',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final a = await repo.createCoffee(
        name: 'House blend',
        roaster: 'A',
        initialGrams: 7,
        roastDate: '2026-11-01',
      );
      final b = await repo.createCoffee(
        name: 'Kenya',
        roaster: 'B',
        initialGrams: 13,
      );
      final first = (await repo.coffeeLots(a)).single;
      final second = (await repo.coffeeLots(b)).single;
      await repo.freezeCoffee(
        lotId: second.id,
        grams: 3,
        frozenDate: '2026-11-10',
      );
      final mix = await repo.blends.create('Ends', {
        first.id: 7,
        second.id: 10,
      });
      final lot = (await repo.coffeeLots(mix.id)).single;
      expect(lot.remainingGrams, 17);
      expect(lot.roastDate, isNull);
      expect(
        (await repo.blends.contributions(mix.id)).map((r) => r.sourceRoastDate),
        unorderedEquals(['2026-11-01', null]),
      );
      expect(mix.empty.map((c) => c.id), [a]);
      final history = await repo.stockAdjustments(a);
      expect(
        CoffeeStock(
          lots: await repo.coffeeLots(a),
          portions: [],
          adjustments: history,
        ).consumedGrams,
        0,
      );
      await expectLater(
        repo.undoStockAdjustment(history.single.operationId),
        throwsA(isA<StockAdjustmentException>()),
      );
      await repo.blends.archiveEmpty({a: 8, b: 9});
      expect((await repo.records.coffee(a))!.rating, 8);
      expect((await repo.records.coffee(b))!.archivedAtMs, isNull);
      final backup = JournalBackup(db);
      await backup.restoreJson(await backup.exportJson());
      expect((await repo.blends.contributions(mix.id)).length, 2);
      final c = await repo.createCoffee(
        name: 'Next',
        roaster: 'C',
        initialGrams: 50,
      );
      final next = (await repo.coffeeLots(c)).single;
      await expectLater(
        repo.blends.create('Nested', {next.id: 2, lot.id: 5}),
        throwsStateError,
      );
      expect((await repo.coffeeLot(next.id))!.remainingGrams, 50);
      expect((await repo.coffeeLot(lot.id))!.remainingGrams, 17);
      expect(await repo.records.allBrews(), isEmpty);
      await repo.createBrew(
        coffeeId: mix.id,
        lotId: lot.id,
        methodName: 'V60',
        doseGrams: 10,
      );
      expect((await repo.coffeeLot(lot.id))!.remainingGrams, 7);
      expect((await repo.coffeeLot(first.id))!.remainingGrams, 0);
      expect((await repo.coffeeLot(second.id))!.remainingGrams, 0);
      expect((await repo.records.allBrews()).length, 1);
    },
  );
}
