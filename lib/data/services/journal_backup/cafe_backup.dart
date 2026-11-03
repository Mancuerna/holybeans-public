part of '../journal_backup.dart';

class _CafeBackup {
  _CafeBackup(Map<String, dynamic> data, this.keepPhoto)
    : legacy = !data.containsKey('roasters'),
      roasters = _decode(
        {
          ...data,
          'roasters': data.containsKey('roasters')
              ? data['roasters']
              : <dynamic>[],
        },
        'roasters',
        Roaster.fromJson,
      ),
      links = _decode(
        {
          ...data,
          'coffeeRoasterLinks': data.containsKey('coffeeRoasterLinks')
              ? data['coffeeRoasterLinks']
              : <dynamic>[],
        },
        'coffeeRoasterLinks',
        CoffeeRoasterLink.fromJson,
      ),
      cafes = _decode(
        {
          ...data,
          'cafes': data.containsKey('cafes') ? data['cafes'] : <dynamic>[],
        },
        'cafes',
        Cafe.fromJson,
      ),
      drinks = _decode(
        {
          ...data,
          'cafeDrinks': data.containsKey('cafeDrinks')
              ? data['cafeDrinks']
              : <dynamic>[],
        },
        'cafeDrinks',
        CafeDrink.fromJson,
      ),
      photos = _decode(
        {
          ...data,
          'cafeDrinkPhotos': data.containsKey('cafeDrinkPhotos')
              ? data['cafeDrinkPhotos']
              : <dynamic>[],
        },
        'cafeDrinkPhotos',
        CafeDrinkPhoto.fromJson,
      );
  final bool legacy;
  final bool Function(String) keepPhoto;
  final List<Roaster> roasters;
  final List<CoffeeRoasterLink> links;
  final List<Cafe> cafes;
  final List<CafeDrink> drinks;
  final List<CafeDrinkPhoto> photos;

  void validate(List<Coffee> coffees) {
    _ensureUnique(roasters.map((r) => r.id), 'roaster');
    _ensureUnique(roasters.map((r) => r.nameKey), 'roaster key');
    _ensureUnique(links.map((r) => r.coffeeId), 'coffee roaster link');
    _ensureUnique(cafes.map((r) => r.id), 'cafe');
    _ensureUnique(
      cafes.map((r) => r.sourceKey).whereType<String>(),
      'cafe source',
    );
    _ensureUnique(drinks.map((r) => r.id), 'cafe drink');
    _ensureUnique(
      photos.map((r) => _photoKey(r.drinkId, r.position)),
      'cafe photo',
    );
    final roasterIds = {for (final r in roasters) r.id};
    final coffeeIds = {for (final c in coffees) c.id};
    final cafeIds = {for (final c in cafes) c.id};
    final drinkIds = {for (final d in drinks) d.id};
    for (final r in roasters) {
      if (r.id.isEmpty ||
          r.name.trim().isEmpty ||
          r.name.length > 200 ||
          r.nameKey != roasterKey(r.name)) {
        throw const FormatException('Invalid roaster');
      }
    }
    for (final l in links) {
      if (!coffeeIds.contains(l.coffeeId) ||
          !roasterIds.contains(l.roasterId)) {
        throw const FormatException('Invalid coffee roaster link');
      }
    }
    for (final c in cafes) {
      if (c.id.isEmpty) throw const FormatException('Invalid cafe ID');
      CafeInput(
        name: c.name,
        latitude: c.latitude,
        longitude: c.longitude,
      ).validate();
    }
    for (final d in drinks) {
      if (d.id.isEmpty ||
          !cafeIds.contains(d.cafeId) ||
          (d.roasterId != null && !roasterIds.contains(d.roasterId))) {
        throw const FormatException('Invalid cafe drink relation');
      }
      CafeDrinkInput(
        cafe: const CafeInput(name: 'validated'),
        drinkType: d.drinkType,
        drankAt: DateTime.fromMillisecondsSinceEpoch(d.drankAtMs),
        rating: d.rating,
        priceCents: d.priceCents,
        currency: d.currency,
      ).validate();
    }
    for (final p in photos) {
      if (!drinkIds.contains(p.drinkId) ||
          p.position < 0 ||
          !PhotoStore.isValidName(p.fileName)) {
        throw const FormatException('Invalid cafe photo');
      }
    }
  }

  Future<void> write(AppDatabase database) async {
    await database.batch((b) {
      b.insertAll(database.roasters, roasters);
      b.insertAll(database.coffeeRoasterLinks, links);
      b.insertAll(database.cafes, cafes);
      b.insertAll(database.cafeDrinks, drinks);
      final sorted = [...photos]
        ..sort(
          (a, b) => _photoKey(
            a.drinkId,
            a.position,
          ).compareTo(_photoKey(b.drinkId, b.position)),
        );
      b.insertAll(
        database.cafeDrinkPhotos,
        _numbered(
          [
            for (final p in sorted)
              if (keepPhoto(p.fileName)) (p.drinkId, p.fileName),
          ],
          (owner, position, name) => CafeDrinkPhoto(
            drinkId: owner,
            position: position,
            fileName: name,
          ),
        ),
      );
    });
    if (legacy) await RoasterRegistry(database).backfill();
  }

  static Future<void> clear(AppDatabase database) async {
    await database.delete(database.cafeDrinkPhotos).go();
    await database.delete(database.cafeDrinks).go();
    await database.delete(database.coffeeRoasterLinks).go();
    await database.delete(database.cafes).go();
    await database.delete(database.roasters).go();
  }
}
