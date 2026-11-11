import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/shot_curve.dart';

import 'helpers/test_database.dart';

void main() {
  test(
    'references include only espresso pressure and never change source data',
    () async {
      final db = memoryDatabase();
      final repo = JournalRepository(db);
      try {
        final coffee = await repo.createCoffee(
          name: 'Reference',
          roaster: 'Test',
        );
        final espresso = await repo.createMethod(
          name: 'Lever',
          category: 'espresso',
        );
        final filter = await repo.createMethod(
          name: 'V60',
          category: 'pourover',
        );
        final ids = <String>[];
        for (final method in [espresso, filter, espresso]) {
          ids.add(
            await repo.createBrew(
              coffeeId: coffee,
              methodId: method,
              methodName: method == espresso ? 'Lever' : 'V60',
              doseGrams: 18,
            ),
          );
        }
        for (var i = 0; i < ids.length; i++) {
          await repo.saveScaleCurve(
            ids[i],
            ShotCurve(
              timesMs: [0, 1000, 3000],
              pressure: i == 2 ? [] : [0, 9, 6],
              flow: [],
              weight: [0, 1, 5],
            ),
          );
        }
        final before = (await repo.brewCurve(ids.first))!.curve.toJson();
        final references = await repo.pressureReferences();
        expect(references.map((r) => r.brew.id), [ids.first]);
        expect(references.single.guide.targetAt(2000), 7.5);
        expect((await repo.brewCurve(ids.first))!.curve.toJson(), before);
        expect((await repo.allBrews()).length, 3);
      } finally {
        await db.close();
      }
    },
  );
}
