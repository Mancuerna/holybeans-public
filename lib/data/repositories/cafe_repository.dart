import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_journal.dart';
import 'package:uuid/uuid.dart';

class CafeJournalData {
  const CafeJournalData(this.cafes, this.drinks, this.roasters, this.photos);
  final List<Cafe> cafes;
  final List<CafeDrink> drinks;
  final List<Roaster> roasters;
  final List<CafeDrinkPhoto> photos;
  Cafe cafeOf(CafeDrink drink) => cafes.firstWhere((c) => c.id == drink.cafeId);
  String? roasterOf(CafeDrink drink) {
    for (final r in roasters) {
      if (r.id == drink.roasterId) return r.name;
    }
    return null;
  }

  List<String> photosOf(String id) => [
    for (final p in photos)
      if (p.drinkId == id) p.fileName,
  ];
}

/// Cafe writes never touch brewing inventory or home preparation rows.
class CafeRepository {
  CafeRepository(this.database);
  final AppDatabase database;
  static String? _clean(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  Future<CafeJournalData> read() => database.transaction(
    () async => CafeJournalData(
      await (database.select(
        database.cafes,
      )..orderBy([(r) => OrderingTerm.asc(r.name)])).get(),
      await (database.select(
        database.cafeDrinks,
      )..orderBy([(r) => OrderingTerm.desc(r.drankAtMs)])).get(),
      await (database.select(
        database.roasters,
      )..orderBy([(r) => OrderingTerm.asc(r.name)])).get(),
      await (database.select(
        database.cafeDrinkPhotos,
      )..orderBy([(r) => OrderingTerm.asc(r.position)])).get(),
    ),
  );

  Stream<CafeJournalData> watch() => database
      .customSelect(
        'SELECT 1',
        readsFrom: {
          database.cafes,
          database.cafeDrinks,
          database.roasters,
          database.cafeDrinkPhotos,
        },
      )
      .watch()
      .asyncMap((_) => read());

  Future<String> save(CafeDrinkInput input) async {
    input.validate();
    if (input.photos.any((p) => !PhotoStore.isValidName(p)) ||
        input.photos.toSet().length != input.photos.length) {
      throw const FormatException('Invalid cafe photos');
    }
    return database.transaction(() async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final id = input.id ?? const Uuid().v4();
      final previous = await (database.select(
        database.cafeDrinks,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (input.id != null && previous == null) {
        throw StateError('Cafe drink not found');
      }
      final venue = input.cafe;
      Cafe? oldCafe;
      if (venue.id != null) {
        oldCafe = await (database.select(
          database.cafes,
        )..where((r) => r.id.equals(venue.id!))).getSingleOrNull();
        if (oldCafe == null) throw StateError('Cafe not found');
      } else if (venue.sourceKey != null) {
        oldCafe =
            await (database.select(database.cafes)
                  ..where((r) => r.sourceKey.equals(venue.sourceKey!)))
                .getSingleOrNull();
      }
      final cafeId = oldCafe?.id ?? const Uuid().v4();
      // A stale catalog suggestion must not erase details already entered for
      // this source. Selecting the saved venue explicitly still allows edits.
      String? venueDetail(String? value, String? saved) =>
          venue.id == null ? _clean(value) ?? saved : _clean(value);
      await database
          .into(database.cafes)
          .insertOnConflictUpdate(
            Cafe(
              id: cafeId,
              name: venue.name.trim(),
              country: venueDetail(venue.country, oldCafe?.country),
              city: venueDetail(venue.city, oldCafe?.city),
              address: venueDetail(venue.address, oldCafe?.address),
              latitude: venue.latitude,
              longitude: venue.longitude,
              sourceKey: venue.sourceKey,
              sourceUrl: venue.sourceUrl,
              createdAtMs: oldCafe?.createdAtMs ?? now,
              updatedAtMs: now,
            ),
          );
      final roaster = await RoasterRegistry(database).resolve(input.roaster);
      await database
          .into(database.cafeDrinks)
          .insertOnConflictUpdate(
            CafeDrink(
              id: id,
              cafeId: cafeId,
              roasterId: roaster,
              drinkType: input.drinkType.trim(),
              coffeeName: _clean(input.coffeeName),
              originCountry: _clean(input.originCountry),
              process: _clean(input.process),
              variety: _clean(input.variety),
              notes: _clean(input.notes),
              rating: input.rating,
              priceCents: input.priceCents,
              currency: input.currency,
              drankAtMs: input.drankAt.toUtc().millisecondsSinceEpoch,
              createdAtMs: previous?.createdAtMs ?? now,
              updatedAtMs: now,
            ),
          );
      await (database.delete(
        database.cafeDrinkPhotos,
      )..where((r) => r.drinkId.equals(id))).go();
      await database.batch(
        (batch) => batch.insertAll(database.cafeDrinkPhotos, [
          for (var i = 0; i < input.photos.length; i++)
            CafeDrinkPhoto(drinkId: id, position: i, fileName: input.photos[i]),
        ]),
      );
      return id;
    });
  }

  Future<void> deletePhotoIfUnused(PhotoStore? store, String name) async {
    if (store == null) return;
    final used = await database
        .customSelect(
          'SELECT 1 FROM coffee_photos WHERE file_name = ? '
          'UNION ALL SELECT 1 FROM brew_photos WHERE file_name = ? '
          'UNION ALL SELECT 1 FROM cafe_drink_photos WHERE file_name = ? LIMIT 1',
          variables: [
            Variable.withString(name),
            Variable.withString(name),
            Variable.withString(name),
          ],
        )
        .get();
    if (used.isEmpty) await store.delete(name);
  }

  Future<void> delete(String id) => database.transaction(() async {
    await (database.delete(
      database.cafeDrinkPhotos,
    )..where((r) => r.drinkId.equals(id))).go();
    await (database.delete(
      database.cafeDrinks,
    )..where((r) => r.id.equals(id))).go();
  });
}
