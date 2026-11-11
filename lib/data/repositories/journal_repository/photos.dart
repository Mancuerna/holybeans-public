part of '../journal_repository.dart';

/// Ordered photos of coffees and brews; the first one is the cover. The
/// files live in the photo folder and the rows only name them.
extension PhotoOperations on JournalRepository {
  /// Most photos kept for one coffee or brew.
  static const maxPhotos = 8;

  Stream<List<String>> watchCoffeePhotos(String coffeeId) =>
      (database.select(database.coffeePhotos)
            ..where((row) => row.coffeeId.equals(coffeeId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .map((row) => row.fileName)
          .watch();

  Future<List<String>> coffeePhotos(String coffeeId) =>
      (database.select(database.coffeePhotos)
            ..where((row) => row.coffeeId.equals(coffeeId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .map((row) => row.fileName)
          .get();

  Stream<List<String>> watchBrewPhotos(String brewId) =>
      (database.select(database.brewPhotos)
            ..where((row) => row.brewId.equals(brewId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .map((row) => row.fileName)
          .watch();

  Future<List<String>> brewPhotos(String brewId) =>
      (database.select(database.brewPhotos)
            ..where((row) => row.brewId.equals(brewId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .map((row) => row.fileName)
          .get();

  Future<List<String>> _unreferencedPhotos(List<String> files) async {
    final candidates = files.toSet().toList();
    final referenced = <String>{};
    Future<void> collect<T extends Table, D>(
      TableInfo<T, D> table,
      GeneratedColumn<String> column,
      List<String> batch,
    ) async {
      final rows =
          await (database.selectOnly(table, distinct: true)
                ..addColumns([column])
                ..where(column.isIn(batch)))
              .get();
      referenced.addAll(rows.map((row) => row.read(column)!));
    }

    // Keep restored journals with unusually many photos within SQLite's
    // parameter limit too. Empty candidates need no reference queries.
    for (var offset = 0; offset < candidates.length; offset += 500) {
      final batch = candidates.sublist(
        offset,
        min(offset + 500, candidates.length),
      );
      await collect(
        database.coffeePhotos,
        database.coffeePhotos.fileName,
        batch,
      );
      await collect(database.brewPhotos, database.brewPhotos.fileName, batch);
    }
    return files.where((name) => !referenced.contains(name)).toList();
  }

  /// The cover photo of every coffee that has one, by coffee ID.
  Stream<Map<String, String>> watchCoffeeCovers() =>
      (database.select(database.coffeePhotos)
            ..where((row) => row.position.equals(0)))
          .watch()
          .map((rows) => {for (final row in rows) row.coffeeId: row.fileName});

  /// Replaces the photos of a coffee with [files], in that order.
  Future<void> setCoffeePhotos(String coffeeId, List<String> files) {
    _checkPhotoNames(files);
    return database.transaction(() async {
      final coffee = await (database.select(
        database.coffees,
      )..where((row) => row.id.equals(coffeeId))).getSingleOrNull();
      if (coffee == null) throw StateError('Coffee not found');
      await (database.delete(
        database.coffeePhotos,
      )..where((row) => row.coffeeId.equals(coffeeId))).go();
      await database.batch(
        (batch) => batch.insertAll(database.coffeePhotos, [
          for (var i = 0; i < files.length; i++)
            CoffeePhoto(coffeeId: coffeeId, position: i, fileName: files[i]),
        ]),
      );
    });
  }

  /// Replaces the photos of a brew with [files], in that order.
  Future<void> setBrewPhotos(String brewId, List<String> files) {
    _checkPhotoNames(files);
    return database.transaction(() async {
      final brew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingleOrNull();
      if (brew == null) throw StateError('Brew not found');
      await (database.delete(
        database.brewPhotos,
      )..where((row) => row.brewId.equals(brewId))).go();
      await database.batch(
        (batch) => batch.insertAll(database.brewPhotos, [
          for (var i = 0; i < files.length; i++)
            BrewPhoto(brewId: brewId, position: i, fileName: files[i]),
        ]),
      );
    });
  }
}

void _checkPhotoNames(List<String> files) {
  if (files.length > PhotoOperations.maxPhotos) {
    throw ArgumentError.value(files.length, 'files', 'Too many photos');
  }
  if (files.toSet().length != files.length) {
    throw ArgumentError.value(files, 'files', 'Repeated photo');
  }
  for (final name in files) {
    if (!PhotoStore.isValidName(name)) throw ArgumentError.value(name, 'files');
  }
}
