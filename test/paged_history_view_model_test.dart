import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/paged_history_view_model.dart';

const HistoryQuery selection = (
  text: '',
  archived: true,
  ascending: false,
  coffeeId: null,
  methodId: null,
  methodName: null,
  startMs: null,
  endMs: null,
  minimumRating: null,
);
Future<void> until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      fail('History did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test(
    'page cache is bounded, reloads evicted rows and follows edits',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(name: 'Coffee', roaster: 'Roaster');
      await db.batch(
        (batch) => batch.insertAll(db.brews, [
          for (var i = 0; i < 850; i++)
            BrewsCompanion.insert(
              id: 'b$i',
              coffeeId: id,
              methodName: 'V60',
              brewedAtMs: i,
              createdAtMs: i,
              updatedAtMs: i,
              notes: Value('Long ${'x' * 2048} $i'),
            ),
        ]),
      );
      final data = JournalData(
        reads: repo.reads,
        coffees: await repo.allCoffees(),
        brews: const [],
        lots: const [],
        components: const [],
      );
      final model = PagedHistoryViewModel(repo.reads);
      addTearDown(() async {
        model.dispose();
        await db.close();
      });
      model.update(data, selection);
      await until(() => !model.busy);
      for (var page = 0; page < 16; page++) {
        final index = page * 50;
        await until(() => model.brewAt(index) != null);
        expect(model.brewAt(index)!.id, 'b${849 - index}');
        expect(model.brewAt(index)!.notes, null);
        expect(model.cachedRows, lessThanOrEqualTo(300));
        model.brewAt(index + 49);
        await until(() => model.length > index + 51);
      }
      await until(() => model.brewAt(0) != null);
      expect(model.brewAt(0)!.id, 'b849');
      expect(model.cachedRows, lessThanOrEqualTo(300));
      await (db.delete(db.brews)..where((row) => row.id.equals('b849'))).go();
      await until(() => model.brewAt(0)?.id == 'b848');
      expect(model.error, null);
    },
  );
  test('new query cancels an obsolete long-note search', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = JournalRepository(db);
    final id = await repo.createCoffee(name: 'Coffee', roaster: 'Roaster');
    await db.batch(
      (batch) => batch.insertAll(db.brews, [
        for (var i = 0; i < 300; i++)
          BrewsCompanion.insert(
            id: 'b$i',
            coffeeId: id,
            methodName: 'V60',
            brewedAtMs: i,
            createdAtMs: i,
            updatedAtMs: i,
            notes: Value('x' * 8192),
          ),
      ]),
    );
    final data = JournalData(
      coffees: await repo.allCoffees(),
      brews: const [],
      lots: const [],
      components: const [],
    );
    final model = PagedHistoryViewModel(repo.reads);
    addTearDown(() async {
      model.dispose();
      await db.close();
    });
    model.update(data, (
      text: 'missing',
      archived: true,
      ascending: false,
      coffeeId: null,
      methodId: null,
      methodName: null,
      startMs: null,
      endMs: null,
      minimumRating: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    model.update(data, selection);
    await until(() => !model.busy);
    expect(model.brewAt(0)!.id, 'b299');
    expect(model.length, 51);
    expect(model.error, null);
  });
}
