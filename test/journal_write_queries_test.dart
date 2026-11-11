import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

class _Queries extends QueryInterceptor {
  int photoRows = 0;
  int brewRows = 0;
  int brewUpdates = 0;
  void reset() => photoRows = brewRows = brewUpdates = 0;
  Map<String, int> get snapshot => {
    'photoRows': photoRows,
    'brewRows': brewRows,
    'brewUpdates': brewUpdates,
  };

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM "coffee_photos"') ||
        statement.contains('FROM "brew_photos"')) {
      photoRows += rows.length;
    }
    if (statement.contains('FROM "brews"')) brewRows += rows.length;
    return rows;
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('UPDATE "brews"')) brewUpdates++;
    return executor.runUpdate(statement, args);
  }
}

CoffeesCompanion _coffee(String id) => CoffeesCompanion.insert(
  id: id,
  name: id,
  roaster: 'Test',
  createdAtMs: 1,
  updatedAtMs: 1,
);
BrewsCompanion _brew(String id, String coffee, {bool archived = false}) =>
    BrewsCompanion.insert(
      id: id,
      coffeeId: coffee,
      methodName: 'V60',
      brewedAtMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
      archivedAtMs: Value(archived ? 2 : null),
    );

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late _Queries counts;
  setUp(() {
    counts = _Queries();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(counts));
    repo = JournalRepository(db);
  });
  tearDown(() => db.close());

  test(
    'photo cleanup reads only candidate references and preserves shared files',
    () async {
      await db.batch((batch) {
        batch.insertAll(db.coffees, [
          for (var i = 0; i < 100; i++) _coffee('coffee-$i'),
          _coffee('unused'),
          _coffee('empty'),
        ]);
        batch.insertAll(db.brews, [
          for (var i = 0; i < 100; i++) _brew('brew-$i', 'coffee-$i'),
          _brew('delete', 'coffee-0'),
        ]);
        batch.insertAll(db.coffeePhotos, [
          for (var i = 0; i < 100; i++)
            CoffeePhoto(
              coffeeId: 'coffee-$i',
              position: 0,
              fileName: i == 0 ? 'shared-coffee.jpg' : 'coffee-$i.jpg',
            ),
          const CoffeePhoto(
            coffeeId: 'unused',
            position: 0,
            fileName: 'unique-coffee.jpg',
          ),
          const CoffeePhoto(
            coffeeId: 'unused',
            position: 1,
            fileName: 'shared-brew.jpg',
          ),
        ]);
        batch.insertAll(db.brewPhotos, [
          for (var i = 0; i < 100; i++)
            BrewPhoto(
              brewId: 'brew-$i',
              position: 0,
              fileName: i == 0 ? 'shared-brew.jpg' : 'brew-$i.jpg',
            ),
          const BrewPhoto(
            brewId: 'delete',
            position: 0,
            fileName: 'unique-brew.jpg',
          ),
          const BrewPhoto(
            brewId: 'delete',
            position: 1,
            fileName: 'shared-coffee.jpg',
          ),
        ]);
      });
      counts.reset();
      expect(await repo.deleteUnusedCoffee('unused'), ['unique-coffee.jpg']);
      final coffeeRows = counts.photoRows;
      counts.reset();
      expect(await repo.deleteBrew('delete'), ['unique-brew.jpg']);
      final brewRows = counts.photoRows;
      counts.reset();
      expect(await repo.deleteUnusedCoffee('empty'), isEmpty);
      final emptyRows = counts.photoRows;
      stdout.writeln(
        'PHOTO_REFERENCE_ROWS ${jsonEncode([coffeeRows, brewRows, emptyRows])}',
      );
      expect(await repo.coffeePhotos('coffee-0'), ['shared-coffee.jpg']);
      expect(await repo.brewPhotos('brew-0'), ['shared-brew.jpg']);
      expect(await db.select(db.coffeePhotos).get(), hasLength(100));
      expect(await db.select(db.brewPhotos).get(), hasLength(100));
      expect([coffeeRows, brewRows, emptyRows], [3, 3, 0]);
    },
  );

  test(
    'restored photo lists preserve order and duplicates across batches',
    () async {
      final files = [
        for (var i = 0; i < 1001; i++) 'file-$i.jpg',
        'file-0.jpg',
      ];
      await db.batch((batch) {
        batch.insertAll(db.coffees, [_coffee('delete'), _coffee('keep')]);
        batch.insertAll(db.coffeePhotos, [
          for (final (position, file) in files.indexed)
            CoffeePhoto(coffeeId: 'delete', position: position, fileName: file),
          const CoffeePhoto(
            coffeeId: 'keep',
            position: 0,
            fileName: 'file-1000.jpg',
          ),
        ]);
      });
      expect(
        await repo.deleteUnusedCoffee('delete'),
        files.where((file) => file != 'file-1000.jpg').toList(),
      );
      expect(await repo.coffeePhotos('keep'), ['file-1000.jpg']);
    },
  );

  test('coffee archive uses one update and preserves independent archives', () async {
    await db.batch((batch) {
      batch.insertAll(db.coffees, [_coffee('coffee'), _coffee('other')]);
      batch.insertAll(db.brews, [
        for (var i = 0; i < 100; i++)
          _brew('brew-$i', 'coffee', archived: i < 10),
        _brew('other-brew', 'other'),
      ]);
    });
    final before = await db.select(db.brews).get();
    final independent = before.where((r) => r.archivedAtMs != null).toList();
    counts.reset();
    await repo.setCoffeeArchived('coffee', archived: true, rating: 8);
    final archive = counts.snapshot;
    final coffee = (await repo.coffee('coffee'))!;
    final archived = await db.select(db.brews).get();
    expect(archived.where((r) => r.archivedByCoffee == true), hasLength(90));
    for (final row in archived.where((r) => r.archivedByCoffee == true)) {
      expect(row.archivedAtMs, coffee.archivedAtMs);
      expect(row.updatedAtMs, coffee.updatedAtMs);
    }
    expect(
      archived.where((r) => independent.any((old) => old.id == r.id)),
      independent,
    );
    expect(archived.singleWhere((r) => r.id == 'other-brew'), before.last);
    counts.reset();
    await repo.setCoffeeArchived('coffee', archived: false);
    final restore = counts.snapshot;
    stdout.writeln(
      'COFFEE_ARCHIVE_QUERIES ${jsonEncode({'archive': archive, 'restore': restore})}',
    );
    final restored = await db.select(db.brews).get();
    expect(
      restored.where((r) => independent.any((old) => old.id == r.id)),
      independent,
    );
    expect(restored.where((r) => r.archivedAtMs == null), hasLength(91));
    expect(restored.where((r) => r.archivedByCoffee == true), isEmpty);
    expect((await repo.coffee('coffee'))!.rating, 8);
    expect(archive, {'photoRows': 0, 'brewRows': 0, 'brewUpdates': 1});
    expect(restore, {'photoRows': 0, 'brewRows': 0, 'brewUpdates': 1});
  });
}
