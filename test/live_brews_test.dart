import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repository;
  late String coffee;
  setUp(() async {
    db = memoryDatabase();
    repository = JournalRepository(db);
    coffee = await repository.createCoffee(name: 'Test', roaster: 'Test');
  });
  tearDown(() => db.close());

  Future<String> add(int day, {String? notes}) => repository.createBrew(
    coffeeId: coffee,
    methodName: 'V60',
    brewedAt: DateTime(2026, 1, day),
    notes: notes,
  );
  Future<List<Brew>> next(StreamIterator<List<Brew>> stream) async {
    expect(await stream.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    return stream.current;
  }

  StreamIterator<List<Brew>> watch({bool archived = true}) {
    final stream = StreamIterator(
      repository.watchBrews(includeArchived: archived),
    );
    addTearDown(stream.cancel);
    return stream;
  }

  test('updates only changed rows, even with unchanged timestamps', () async {
    final first = await add(1, notes: 'long original note');
    final second = await add(2);
    final stream = watch();
    final before = await next(stream);
    expect(before.map((b) => b.id), [second, first]);
    await (db.update(db.brews)..where((b) => b.id.equals(first))).write(
      const BrewsCompanion(
        notes: Value('Changed without touching updated_at_ms'),
      ),
    );
    final after = await next(stream);
    expect(after.first, same(before.first));
    expect(after.last.notes, 'Changed without touching updated_at_ms');
    expect(before.last.notes, 'long original note');
    expect(after.clear, throwsUnsupportedError);
  });

  test('follows deletes, archives, inserts and complete replacement', () async {
    final first = await add(1);
    final active = watch(archived: false);
    final all = watch();
    await next(active);
    await next(all);
    await repository.setBrewArchived(first, archived: true);
    expect(await next(active), isEmpty);
    expect((await next(all)).single.archivedAtMs, isNotNull);
    await repository.setBrewArchived(first, archived: false);
    expect((await next(active)).single.id, first);
    await next(all);
    await db.transaction(() async {
      await db.delete(db.brews).go();
      await add(3, notes: 'restored');
    });
    expect((await next(active)).single.notes, 'restored');
    expect((await next(all)).single.notes, 'restored');
    await db.delete(db.brews).go();
    expect(await next(active), isEmpty);
    expect(await next(all), isEmpty);
  });

  test('rolled-back changes never become a visible snapshot', () async {
    final first = await add(1, notes: 'original');
    final stream = watch();
    await next(stream);
    await expectLater(
      db.transaction(() async {
        await (db.update(db.brews)..where((b) => b.id.equals(first))).write(
          const BrewsCompanion(notes: Value('rolled back')),
        );
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    await add(2);
    expect((await next(stream)).last.notes, 'original');
  });

  test(
    'replacement conflict clauses and changed primary keys stay visible',
    () async {
      final first = await add(1);
      final stream = watch();
      await next(stream);
      final original = (await repository.brew(first))!;
      await db
          .into(db.brews)
          .insert(
            original.copyWith(notes: const Value('replace')),
            mode: InsertMode.insertOrReplace,
          );
      expect((await next(stream)).single.notes, 'replace');
      await db.customUpdate(
        'UPDATE OR IGNORE brews SET notes = ? WHERE id = ?',
        variables: [const Variable('ignored conflict policy'), Variable(first)],
        updates: {db.brews},
      );
      expect((await next(stream)).single.notes, 'ignored conflict policy');
      await (db.update(db.brews)..where((b) => b.id.equals(first))).write(
        const BrewsCompanion(id: Value('renamed')),
      );
      expect((await next(stream)).single.id, 'renamed');
    },
  );

  test(
    'screens share rows and a new subscription sees edits after cancellation',
    () async {
      final id = await add(1, notes: 'shared');
      final first = watch();
      final before = await next(first);
      final second = watch();
      expect((await next(second)).single, same(before.single));
      await first.cancel();
      await second.cancel();
      await (db.update(db.brews)..where((b) => b.id.equals(id))).write(
        const BrewsCompanion(notes: Value('after cancellation')),
      );
      expect((await next(watch())).single.notes, 'after cancellation');
    },
  );

  test(
    'a new subscriber after a write never replays stale cached rows',
    () async {
      final id = await add(1, notes: 'before');
      final first = watch();
      await next(first);
      await (db.update(db.brews)..where((b) => b.id.equals(id))).write(
        const BrewsCompanion(notes: Value('after')),
      );
      expect((await next(watch())).single.notes, 'after');
    },
  );

  test(
    'timestamp ties keep SQLite ordering for non-ASCII imported IDs',
    () async {
      final id = await add(1);
      final base = (await repository.brew(id))!;
      await db.delete(db.brews).go();
      for (final id in ['a', '😀', '\ue000']) {
        await db.into(db.brews).insert(base.copyWith(id: id));
      }
      final ordered = await db
          .customSelect('SELECT id FROM brews ORDER BY id ASC')
          .get();
      expect(
        (await next(watch())).map((row) => row.id),
        ordered.map((row) => row.read<String>('id')),
      );
    },
  );

  test('same-date ordering remains deterministic after edits', () async {
    await add(1);
    await add(1);
    final stream = watch();
    final before = await next(stream);
    await (db.update(db.brews)..where((b) => b.id.equals(before.last.id)))
        .write(const BrewsCompanion(rating: Value(4)));
    expect((await next(stream)).map((b) => b.id), before.map((b) => b.id));
  });
}
