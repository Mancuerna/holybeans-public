import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/freeze_plan.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String lot;
  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    final coffee = await repo.createCoffee(
      name: 'Bulk',
      roaster: 'R',
      initialGrams: 950,
    );
    lot = (await repo.coffeeLots(coffee)).single.id;
  });
  tearDown(() => db.close());
  for (final remainder in [false, true]) {
    test(
      'bulk freezing preserves grams and labels, remainder $remainder',
      () async {
        final ids = await repo.freezeCoffeePortions(
          lotId: lot,
          amounts: FreezePlan(
            totalGrams: 950,
            portionGrams: 100,
          ).amounts(includeRemainder: remainder),
          frozenDate: '2026-10-19',
          container: 'tube',
          notes: 'Batch',
        );
        final portions = await repo.frozenPortionsForLot(lot);
        expect(ids.length, remainder ? 10 : 9);
        expect(portions.map((p) => p.label).toSet().length, ids.length);
        expect(
          portions.every((p) => p.container == 'tube' && p.notes == 'Batch'),
          isTrue,
        );
        expect((await repo.coffeeLot(lot))!.remainingGrams, remainder ? 0 : 50);
        expect(
          portions.fold(0.0, (sum, p) => sum + p.remainingGrams) +
              (await repo.coffeeLot(lot))!.remainingGrams!,
          950,
        );
      },
    );
  }
  test(
    'a failure after the first portion rolls the entire batch back',
    () async {
      await expectLater(
        repo.freezeCoffeePortions(
          lotId: lot,
          amounts: [100, 900],
          frozenDate: '2026-10-19',
        ),
        throwsStateError,
      );
      expect(await repo.frozenPortionsForLot(lot), isEmpty);
      expect((await repo.coffeeLot(lot))!.remainingGrams, 950);
    },
  );
}
