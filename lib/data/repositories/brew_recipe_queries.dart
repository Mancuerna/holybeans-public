import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_recipe_context.dart';

/// Read-only recipe selection, independent of journal writes and their private helpers.
class BrewRecipeQueries {
  BrewRecipeQueries(AppDatabase database, {required this._readToolIds})
    : _database = database;

  final AppDatabase _database;
  final Future<List<String>> Function(String brewId) _readToolIds;

  /// Latest active brew of [coffeeId] with [methodId], to dial in the next;
  /// with [rated], only brews with a rating or an extraction compass.
  Future<Brew?> latestBrewFor({
    required String coffeeId,
    required String methodId,
    bool rated = false,
  }) =>
      (_database.select(_database.brews)
            ..where(
              (brew) =>
                  brew.coffeeId.equals(coffeeId) &
                  brew.methodId.equals(methodId) &
                  brew.archivedAtMs.isNull() &
                  (rated
                      ? brew.rating.isNotNull() | brew.tasteBalance.isNotNull()
                      : const Constant(true)),
            )
            ..orderBy([
              (brew) => OrderingTerm.desc(brew.brewedAtMs),
              (brew) => OrderingTerm.desc(brew.createdAtMs),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// The favourite brew of [coffeeId] with [methodId], unless archived.
  Future<Brew?> favoriteBrewFor({
    required String coffeeId,
    required String methodId,
  }) =>
      (_database.select(_database.brews)
            ..where(
              (brew) =>
                  brew.coffeeId.equals(coffeeId) &
                  brew.methodId.equals(methodId) &
                  brew.isFavorite.equals(true) &
                  brew.archivedAtMs.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  /// The most recent unarchived brew made with [methodId], used to prefill a
  /// new brew with the values last used for that method.
  Future<Brew?> latestBrewForMethod(String methodId) =>
      (_database.select(_database.brews)
            ..where(
              (brew) =>
                  brew.methodId.equals(methodId) & brew.archivedAtMs.isNull(),
            )
            ..orderBy([
              (brew) => OrderingTerm.desc(brew.brewedAtMs),
              (brew) => OrderingTerm.desc(brew.createdAtMs),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// The reference the brew form shows for [coffeeId] with [methodId]: the
  /// favourite recipe, the latest brew, rated if any is (`lastRated`), and
  /// the latest of all (`newest`), whose notes are often for the next one.
  Future<BrewReferences> dialInFor({
    required String coffeeId,
    required String methodId,
  }) async {
    final favorite = await favoriteBrewFor(
      coffeeId: coffeeId,
      methodId: methodId,
    );
    final rated = await latestBrewFor(
      coffeeId: coffeeId,
      methodId: methodId,
      rated: true,
    );
    final newest = await latestBrewFor(coffeeId: coffeeId, methodId: methodId);
    return (
      favorite: favorite,
      last: rated ?? newest,
      lastRated: rated != null,
      newest: newest,
    );
  }

  /// The brew a new one with [methodId] takes its values from, with its
  /// tools: the favourite of [coffeeId] with the method (`favorite`), else
  /// the latest with both, else the latest with the method; null for a
  /// method never used.
  Future<BrewRecipeMemory?> methodMemory({
    required String? coffeeId,
    required String methodId,
  }) async {
    final favorite = coffeeId == null
        ? null
        : await favoriteBrewFor(coffeeId: coffeeId, methodId: methodId);
    final brew =
        favorite ??
        (coffeeId == null
            ? null
            : await latestBrewFor(coffeeId: coffeeId, methodId: methodId)) ??
        await latestBrewForMethod(methodId);
    if (brew == null) return null;
    return (
      brew: brew,
      favorite: favorite != null,
      toolIds: List<String>.unmodifiable(await _readToolIds(brew.id)),
    );
  }
}
