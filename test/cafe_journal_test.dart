import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:holybeans/domain/cafe_stats.dart';
import 'package:holybeans/domain/roaster_profile.dart';

void main() {
  late AppDatabase db;
  late CafeRepository cafes;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cafes = CafeRepository(db);
  });
  tearDown(() => db.close());
  CafeDrinkInput drink({
    String? id,
    String roaster = 'Ineffable',
    double? rating = 8,
    List<String> photos = const [],
    CafeInput? cafe,
  }) => CafeDrinkInput(
    id: id,
    cafe:
        cafe ??
        const CafeInput(
          name: 'La cafetería',
          city: 'Madrid',
          country: 'España',
          sourceKey: 'source:1',
        ),
    drinkType: 'V60',
    drankAt: DateTime(2026, 10, 23),
    roaster: roaster,
    originCountry: 'Kenia',
    process: 'Lavado',
    rating: rating,
    priceCents: 400,
    photos: photos,
  );
  Future<Map<String, dynamic>> rows() async =>
      (jsonDecode(await JournalBackup(db).exportJson())
              as Map<String, dynamic>)['data']
          as Map<String, dynamic>;

  test(
    'cafe drink shares roaster, preserves inventory and feeds home suggestions',
    () async {
      final home = JournalRepository(db);
      final coffeeId = await home.createCoffeeWithComponents(
        name: 'Home beans',
        roaster: 'Ineffable',
        initialGrams: 250,
        components: const [],
      );
      final before = await rows();
      final id = await cafes.save(drink(roaster: '  INEFFABLE  '));
      final after = await rows();
      for (final key in before.keys.where(
        (k) => !{'cafes', 'cafeDrinks', 'cafeDrinkPhotos'}.contains(k),
      )) {
        expect(after[key], before[key], reason: key);
      }
      final data = await cafes.read();
      expect(data.roasters, hasLength(1));
      expect(data.roasterOf(data.drinks.single), 'Ineffable');
      final link = await db.select(db.coffeeRoasterLinks).getSingle();
      expect(link.coffeeId, coffeeId);
      expect(link.roasterId, data.drinks.single.roasterId);
      await cafes.save(drink(id: id, roaster: 'New roaster', rating: 7));
      expect((await cafes.read()).cafes, hasLength(1));
      expect(
        (await home.coffeeSuggestions()).roasters,
        contains('New roaster'),
      );
      expect((await cafes.read()).drinks.single.rating, 7);
      await home.updateCoffee(
        id: coffeeId,
        name: 'Home beans',
        roaster: 'New roaster',
      );
      expect(
        (await db.select(db.coffeeRoasterLinks).getSingle()).roasterId,
        (await cafes.read()).drinks.single.roasterId,
      );
    },
  );

  test(
    'reusing a raw catalog suggestion preserves known venue details',
    () async {
      await cafes.save(drink());
      await cafes.save(
        drink(
          cafe: const CafeInput(name: 'La cafetería', sourceKey: 'source:1'),
        ),
      );
      final data = await cafes.read();
      expect(data.cafes, hasLength(1));
      expect(data.cafes.single.city, 'Madrid');
      expect(data.cafes.single.country, 'España');
      expect(data.drinks, hasLength(2));
    },
  );

  test(
    'storage failure rolls back the new venue and roaster together',
    () async {
      final before = await rows();
      await db.customStatement(
        "CREATE TRIGGER fail_cafe_drink BEFORE INSERT ON cafe_drinks BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(cafes.save(drink()), throwsA(isA<Exception>()));
      expect(await rows(), before);
    },
  );

  test(
    'failed save cannot create a venue or change an existing drink',
    () async {
      await cafes.save(drink());
      final before = await rows();
      await expectLater(
        cafes.save(
          drink(
            id: 'missing',
            cafe: const CafeInput(name: 'Must not persist'),
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        cafes.save(drink(rating: double.nan)),
        throwsFormatException,
      );
      await expectLater(
        cafes.save(drink(photos: ['../unsafe.jpg'])),
        throwsFormatException,
      );
      expect(await rows(), before);
    },
  );

  test(
    'backup restores cafe data and photos, invalid relations roll back',
    () async {
      await cafes.save(
        drink(photos: ['12345678-1234-1234-1234-123456789abc.jpg']),
      );
      final source = await JournalBackup(db).exportJson();
      final before = await rows();
      await JournalBackup(db).restoreJson(
        source,
        availablePhotos: {'12345678-1234-1234-1234-123456789abc.jpg'},
      );
      expect(await rows(), before);
      final broken = jsonDecode(source) as Map<String, dynamic>;
      ((broken['data'] as Map)['cafeDrinks'] as List).first['roasterId'] =
          'missing';
      await expectLater(
        JournalBackup(db).restoreJson(jsonEncode(broken)),
        throwsFormatException,
      );
      expect(await rows(), before);
      await JournalBackup(db).restoreJson(source);
      expect((await cafes.read()).photos, isEmpty);
      expect((await cafes.read()).drinks, hasLength(1));
    },
  );

  test(
    'a null cafe collection is rejected without replacing the diary',
    () async {
      await cafes.save(drink());
      final source = jsonDecode(
        await JournalBackup(db).exportJson(),
      ) as Map<String, dynamic>;
      final before = await rows();
      for (final key in [
        'roasters',
        'coffeeRoasterLinks',
        'cafes',
        'cafeDrinks',
        'cafeDrinkPhotos',
      ]) {
        final broken = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
        (broken['data'] as Map<String, dynamic>)[key] = null;
        await expectLater(
          JournalBackup(db).restoreJson(jsonEncode(broken)),
          throwsFormatException,
        );
        expect(await rows(), before);
      }
    },
  );

  test(
    'legacy backup backfills links without rewriting home records',
    () async {
      await JournalRepository(db).createCoffeeWithComponents(
        name: 'Beans',
        roaster: 'Ineffable',
        components: const [],
      );
      final source = jsonDecode(
        await JournalBackup(db).exportJson(),
      ) as Map<String, dynamic>;
      final data = source['data'] as Map<String, dynamic>;
      for (final key in [
        'roasters',
        'coffeeRoasterLinks',
        'cafes',
        'cafeDrinks',
        'cafeDrinkPhotos',
      ]) {
        data.remove(key);
      }
      source['version'] = 19;
      await JournalBackup(db).restoreJson(jsonEncode(source));
      final after = await rows();
      expect(after['coffees'], data['coffees']);
      expect(after['coffeeRoasterLinks'], hasLength(1));
      expect(after['cafes'], isEmpty);
    },
  );

  test('cafe-only roaster appears without inventing bags or home brews', () {
    final profiles = RoasterProfile.fromJournal(
      coffees: [],
      purchases: [],
      brews: [],
      origins: [],
      cafeDrinks: [
        (
          id: '1',
          roaster: 'Ineffable',
          cafe: 'Cafe',
          drinkType: 'V60',
          origin: 'Kenia',
          rating: 8.0,
        ),
        (
          id: '2',
          roaster: ' ineffable ',
          cafe: 'Cafe',
          drinkType: 'Espresso',
          origin: null,
          rating: null,
        ),
      ],
    );
    final p = profiles.single;
    expect(p.coffees, isEmpty);
    expect(p.brewCount, 0);
    expect(p.cafeDrinks, hasLength(2));
    expect(p.cafeRating, 8);
    final stats = CafeStats([
      (cafeId: '1', rating: 8.0, priceCents: 400, currency: 'EUR'),
      (cafeId: '1', rating: null, priceCents: 500, currency: 'USD'),
      (cafeId: '2', rating: 6.0, priceCents: null, currency: 'EUR'),
    ]);
    expect(stats.averageRating, 7);
    expect(stats.cafeCount, 2);
    expect(stats.spending, {'EUR': 400, 'USD': 500});
  });
}
