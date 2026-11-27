import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_corrections.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository journal;
  late CoffeeCorrections repo;
  setUp(() {
    db = memoryDatabase();
    journal = JournalRepository(db);
    repo = CoffeeCorrections(db);
  });
  tearDown(() => db.close());

  for (final field in CorrectionField.values.where(
    (f) => f != CorrectionField.roaster,
  )) {
    test('corrects only the selected ${field.name} of a blend', () async {
      const part = CoffeeComponentInput(
        country: 'Old',
        region: 'Old',
        farm: 'Old',
        producer: 'Old',
        variety: 'Old',
        process: 'Old',
        altitudeMeters: 1800,
        harvest: '2025',
      );
      final id = await journal.createCoffeeWithComponents(
        name: 'Old',
        roaster: 'Old',
        notes: 'Old',
        components: [part, part],
        initialGrams: 200,
      );
      final before = await journal.coffeeComponents(id);
      final lots = await journal.coffeeLots(id);
      final rows = await repo.rows(field, archived: false);
      expect(rows.map((r) => r.position), [0, 1]);
      await repo.apply(field, {rows.first}, " O'Brien ");
      final after = await journal.coffeeComponents(id);
      final expected = before.first.toJson()..[field.name] = "O'Brien";
      expect(after.first.toJson(), expected);
      expect(after.last, before.last);
      expect(await journal.coffeeLots(id), lots);
      final coffee = (await journal.coffee(id))!;
      expect([coffee.name, coffee.roaster, coffee.notes], everyElement('Old'));
    });
  }

  test('archive scope and stale preview reject the entire selection', () async {
    await journal.createCoffee(name: 'A', roaster: 'Typo');
    final id = await journal.createCoffee(name: 'B', roaster: 'Typo');
    final before = await repo.rows(CorrectionField.roaster, archived: false);
    await (db.update(db.coffees)..where((r) => r.id.equals(id))).write(
      const CoffeesCompanion(archivedAtMs: Value(1)),
    );
    expect(
      await repo.rows(CorrectionField.roaster, archived: false),
      hasLength(1),
    );
    await expectLater(
      repo.apply(CorrectionField.roaster, before.toSet(), 'Correct'),
      throwsA(isA<CorrectionConflict>()),
    );
    final all = await repo.rows(CorrectionField.roaster, archived: true);
    expect(all.map((r) => r.value), everyElement('Typo'));
    expect(await repo.roasterNames(), ['Typo']);
    await repo.apply(CorrectionField.roaster, {all.last}, 'Correct');
    expect((await journal.coffee(id))!.roaster, 'Correct');
  });

  test(
    'reuses the chosen roaster profile and retains other coffee links',
    () async {
      final id = await journal.createCoffee(name: 'A', roaster: 'Nomda');
      final other = await journal.createCoffee(name: 'B', roaster: 'Nomda');
      final dest = await RoasterRegistry(db).resolve('Nomad Coffee');
      final old = await RoasterRegistry(db).resolve('Nomda');
      final rows = await repo.rows(CorrectionField.roaster, archived: false);
      await repo.apply(CorrectionField.roaster, {
        rows.first,
      }, '  Nomad  Coffee ');
      expect((await journal.coffee(id))!.roaster, 'Nomad Coffee');
      final links = {
        for (final r in await db.select(db.coffeeRoasterLinks).get())
          r.coffeeId: r.roasterId,
      };
      expect(links, {id: dest, other: old});
      expect(
        await repo.roasterNames(),
        unorderedEquals(['Nomda', 'Nomad Coffee']),
      );
    },
  );

  test(
    'ignores empty origins and rejects empty or oversized destinations',
    () async {
      await journal.createCoffee(name: 'A', roaster: 'R', region: 'r');
      expect(await repo.rows(CorrectionField.country, archived: true), isEmpty);
      final rows = (await repo.rows(
        CorrectionField.roaster,
        archived: true,
      )).toSet();
      for (final bad in ['   ', 'a' * 201]) {
        await expectLater(
          repo.apply(CorrectionField.roaster, rows, bad),
          throwsArgumentError,
        );
      }
      expect(await repo.roasterNames(), ['R']);
    },
  );

  test('a concurrent spelling edit invalidates the preview', () async {
    final id = await journal.createCoffee(name: 'A', roaster: 'One');
    final rows = await repo.rows(CorrectionField.roaster, archived: false);
    await journal.updateCoffee(id: id, name: 'A', roaster: 'Two');
    await expectLater(
      repo.apply(CorrectionField.roaster, rows.toSet(), 'Three'),
      throwsA(isA<CorrectionConflict>()),
    );
    expect((await journal.coffee(id))!.roaster, 'Two');
  });

  test(
    'a failed batch rolls back earlier assignments and the new profile',
    () async {
      await journal.createCoffee(name: 'A', roaster: 'Old');
      await journal.createCoffee(name: 'B', roaster: 'Old');
      final rows = await repo.rows(CorrectionField.roaster, archived: false);
      final links = await db.select(db.coffeeRoasterLinks).get();
      await db.customStatement(
        "CREATE TRIGGER reject_second BEFORE UPDATE OF roaster ON coffees WHEN OLD.name = 'B' "
        "BEGIN SELECT RAISE(ABORT, 'second coffee failed'); END",
      );
      await expectLater(
        repo.apply(CorrectionField.roaster, rows.toSet(), 'New'),
        throwsA(isA<Exception>()),
      );
      expect(await repo.rows(CorrectionField.roaster, archived: false), rows);
      expect(await repo.roasterNames(), ['Old']);
      expect(await db.select(db.coffeeRoasterLinks).get(), links);
    },
  );
}
