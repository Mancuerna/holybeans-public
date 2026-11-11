import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/favorite_brews.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/test_database.dart';

void main() {
  test(
    'one favourite per coffee and method: best, then rated, then latest',
    () {
      FavoriteCandidate candidate(
        String id, {
        String method = 'v60',
        bool best = false,
        double? rating,
        int at = 0,
      }) => (
        id: id,
        coffeeId: 'kenya',
        methodId: method,
        best: best,
        rating: rating,
        brewedAtMs: at,
      );
      expect(
        pickFavorites([
          candidate('rated', rating: 9),
          candidate('best', best: true, rating: 5),
          candidate('espresso-old', method: 'espresso', at: 1),
          candidate('espresso-new', method: 'espresso', at: 2),
          candidate('espresso-unrated-later', method: 'espresso', at: 3),
          candidate('espresso-rated', method: 'espresso', rating: 6),
        ]),
        {'best', 'espresso-rated'},
      );
    },
  );

  group('in the journal', () {
    late AppDatabase database;
    late JournalRepository repository;
    late String kenya;
    late String v60;
    late String espresso;

    setUp(() async {
      database = memoryDatabase();
      repository = JournalRepository(database);
      kenya = await repository.createCoffee(name: 'Kenya', roaster: 'R');
      v60 = await repository.createMethod(name: 'V60', category: 'pourover');
      espresso = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
    });

    tearDown(() => database.close());

    Future<String> brew(String methodId, String name, {int daysAgo = 0}) =>
        repository.createBrew(
          coffeeId: kenya,
          methodId: methodId,
          methodName: name,
          doseGrams: 18,
          brewedAt: DateTime.now().subtract(Duration(days: daysAgo)),
        );

    Future<Set<String>> favorites() async => {
      for (final row in await (database.select(
        database.brews,
      )..where((row) => row.isFavorite.equals(true))).get())
        row.id,
    };

    test(
      'a new favourite replaces the one of its coffee and method only',
      () async {
        final first = await brew(v60, 'V60', daysAgo: 2);
        final second = await brew(v60, 'V60', daysAgo: 1);
        final shot = await brew(espresso, 'Espresso');
        await repository.setBrewFavorite(first, favorite: true);
        await repository.setBrewFavorite(shot, favorite: true);
        await repository.setBrewFavorite(second, favorite: true);
        expect(await favorites(), {second, shot});
        expect(
          (await repository.favoriteBrewFor(
            coffeeId: kenya,
            methodId: v60,
          ))?.id,
          second,
        );
        // Marking is not an edit, so BeanConqueror updates still apply.
        final before = (await repository.brew(first))!.updatedAtMs;
        await repository.setBrewFavorite(first, favorite: true);
        expect((await repository.brew(first))!.updatedAtMs, before);

        await repository.setBrewFavorite(first, favorite: false);
        expect(await favorites(), {shot});
        await repository.setBrewArchived(shot, archived: true);
        expect(
          await repository.favoriteBrewFor(coffeeId: kenya, methodId: espresso),
          isNull,
          reason: 'an archived brew is no recipe to start from',
        );
      },
    );

    test('editing keeps the favourite unless the method changes', () async {
      final id = await brew(v60, 'V60');
      await repository.setBrewFavorite(id, favorite: true);
      Future<void> save(String methodId, String name) =>
          repository.saveBrewWithOutcome(
            BrewInput(
              coffeeId: kenya,
              methodId: methodId,
              methodName: name,
              doseGrams: 17,
            ),
            id: id,
          );
      await save(v60, 'V60');
      expect(await favorites(), {id});
      await save(espresso, 'Espresso');
      expect(await favorites(), isEmpty);
    });

    test('backups keep favourites and older ones arrive without', () async {
      final id = await brew(v60, 'V60');
      await repository.setBrewFavorite(id, favorite: true);
      final backup = JournalBackup(database);
      final json = await backup.exportJson();
      expect(jsonDecode(json)['version'], JournalBackup.version);

      final copy = memoryDatabase();
      addTearDown(copy.close);
      await JournalBackup(copy).restoreJson(json);
      expect((await copy.select(copy.brews).getSingle()).isFavorite, isTrue);

      // A v21 copy has no such field.
      final old = jsonDecode(json) as Map<String, dynamic>;
      old['version'] = 21;
      for (final row in (old['data'] as Map)['brews'] as List) {
        (row as Map).remove('isFavorite');
      }
      final older = memoryDatabase();
      addTearDown(older.close);
      await JournalBackup(older).restoreJson(jsonEncode(old));
      expect((await older.select(older.brews).getSingle()).isFavorite, isFalse);

      // Two favourites for one coffee and method cannot be restored.
      final twice = jsonDecode(json) as Map<String, dynamic>;
      final brews = (twice['data'] as Map)['brews'] as List;
      brews.add({...(brews.single as Map), 'id': 'other'});
      final broken = memoryDatabase();
      addTearDown(broken.close);
      await expectLater(
        JournalBackup(broken).restoreJson(jsonEncode(twice)),
        throwsFormatException,
      );
    });
  });

  test('BeanConqueror favourites arrive, and local ones win', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    Map<String, dynamic> shot(
      String id, {
      required double rating,
      bool favourite = false,
      bool best = false,
    }) => {
      ...(exportJson()['BREWS'] as List).single as Map<String, dynamic>,
      'config': config(id, DateTime(2025, 1, 5, 8)),
      'rating': rating,
      'favourite': favourite,
      'best_brew': best,
    };
    Future<void> import(List<Map<String, dynamic>> brews) async {
      final json = {...exportJson(), 'BREWS': brews};
      final export = BeanconquerorArchive.read(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      await repository.importBeanconqueror(
        planBeanconquerorImport(
          export,
          await repository.beanconquerorJournal(),
          now: DateTime.utc(2026),
        ),
      );
    }

    Future<Set<double?>> favoriteRatings() async => {
      for (final row in await (database.select(
        database.brews,
      )..where((row) => row.isFavorite.equals(true))).get())
        row.rating,
    };

    await import([
      shot('a', rating: 3, favourite: true),
      shot('b', rating: 4, favourite: true),
      shot('c', rating: 5),
    ]);
    // 4 and 3 of 5 are 8 and 6 of 10.
    expect(await favoriteRatings(), {8.0});

    // Marked as best brew there later: the pair has a favourite here.
    await import([
      shot('a', rating: 3, best: true),
      shot('b', rating: 4, favourite: true),
      shot('c', rating: 5),
    ]);
    expect(await favoriteRatings(), {8.0});
  });
}
