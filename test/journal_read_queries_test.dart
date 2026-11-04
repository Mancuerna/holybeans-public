import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/equipment_overview.dart';
import 'package:holybeans/data/repositories/history_pages.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

const HistoryQuery query = (
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

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String coffee;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(name: 'Café', roaster: 'North');
    await db.batch((batch) {
      batch.insertAll(db.brews, [
        for (var i = 0; i < 160; i++)
          BrewsCompanion.insert(
            id: 'brew-${i.toString().padLeft(3, '0')}',
            coffeeId: coffee,
            methodName: 'V60',
            brewedAtMs: i ~/ 3,
            createdAtMs: i,
            updatedAtMs: 1,
            notes: Value('${'x' * 8192} Cítrico $i'),
            doseGrams: Value(i.toDouble()),
            rating: const Value(8),
          ),
      ]);
    });
  });
  tearDown(() => db.close());

  test(
    'overview retains complete aggregates and bounded previews without notes',
    () async {
      final overview = await repo.reads.overview(
        now: DateTime.fromMillisecondsSinceEpoch(100),
      );
      expect(overview.count, 160);
      expect(overview.byCoffee[coffee]!.ratingSum, 1280);
      expect(overview.weekCount, 160);
      expect(
        overview.weekCountAt(DateTime.fromMillisecondsSinceEpoch(100)),
        160,
      );
      expect(
        overview.weekCountAt(
          DateTime.fromMillisecondsSinceEpoch(100).add(const Duration(days: 8)),
        ),
        0,
      );
      expect(overview.previews, hasLength(3));
      expect(overview.previews.every((row) => row.notes == null), isTrue);
      expect(overview.doses[coffee], 157);
      expect(overview.latestActive.single.id, 'brew-159');
      expect((await repo.brew('brew-159'))!.notes, contains('Cítrico'));
    },
  );

  test('keyset pages retain SQL ordering across ties and both directions', () async {
    final pages = HistoryPages(repo.reads);
    for (final ascending in [false, true]) {
      final selection = (
        text: '',
        archived: true,
        ascending: ascending,
        coffeeId: null as String?,
        methodId: null as String?,
        methodName: null as String?,
        startMs: null as int?,
        endMs: null as int?,
        minimumRating: null as double?,
      );
      final ids = <String>[];
      HistoryCursor? cursor;
      var more = true;
      while (more) {
        final page = await pages.page(selection, [], after: cursor);
        expect(page.rows.length, lessThanOrEqualTo(50));
        expect(page.rows.every((row) => row.notes == null), isTrue);
        ids.addAll(page.rows.map((row) => row.id));
        more = page.more;
        cursor = page.next;
      }
      final expected = await db
          .customSelect(
            'SELECT id FROM brews ORDER BY brewed_at_ms ${ascending ? 'ASC' : 'DESC'}, created_at_ms DESC, id ASC',
          )
          .get();
      expect(ids, expected.map((row) => row.read<String>('id')));
      expect(ids.toSet(), hasLength(160));
    }
  });

  test(
    'search finds old long notes without retaining them in previews',
    () async {
      const selection = (
        text: 'citrico 0',
        archived: true,
        ascending: false,
        coffeeId: null,
        methodId: null,
        methodName: null,
        startMs: null,
        endMs: null,
        minimumRating: null,
      );
      final page = await HistoryPages(repo.reads)
          .page(selection, await repo.allCoffees());
      expect(page.rows.single.id, 'brew-000');
      expect(page.rows.single.notes, isNull);
      expect(page.more, isFalse);
    },
  );

  test(
    'equipment and recipient summaries include the complete history',
    () async {
      final method = await repo.createMethod(name: 'V60');
      final grinder = await repo.createGrinder(name: 'Mill');
      final recipient = await repo.saveRecipient(name: 'Cup', emptyGrams: 120);
      await db
          .update(db.brews)
          .write(
            BrewsCompanion(
              methodId: Value(method),
              grinderId: Value(grinder),
              recipientId: Value(recipient.id),
              grindSetting: const Value(' 12 '),
            ),
          );
      await (db.update(
        db.brews,
      )..where((row) => row.id.equals('brew-159'))).write(
        const BrewsCompanion(
          grindSetting: Value('14'),
          archivedAtMs: Value(10),
        ),
      );
      expect((await repo.reads.watchRecipientUses().first)[recipient.id], 160);
      final overview = await repo.reads.watchEquipment().first;
      expect(overview.methods[method], (count: 160, rating: 8.0, lastMs: 53));
      expect(overview.grinders[grinder]!.brewCount, 160);
      expect(overview.grinders[grinder]!.usualSettings.single, (
        method: 'V60',
        setting: '12',
      ));
    },
  );

  test(
    'a mutation invalidates a cursor revision instead of mixing snapshots',
    () async {
      final pages = HistoryPages(repo.reads);
      final first = await pages.page(query, []);
      await (db.delete(
        db.brews,
      )..where((row) => row.id.equals('brew-000'))).go();
      await expectLater(
        pages.page(
          query,
          [],
          after: first.next,
          expectedRevision: first.revision,
        ),
        throwsA(isA<StaleHistoryPage>()),
      );
      expect((await repo.reads.overview()).count, 159);
    },
  );
}
