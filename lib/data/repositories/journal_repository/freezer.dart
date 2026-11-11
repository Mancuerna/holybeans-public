part of '../journal_repository.dart';

extension FreezerOperations on JournalRepository {
  Stream<List<FrozenPortion>> watchFrozenPortions() =>
      freezer.watchFrozenPortions();
  Future<List<FrozenPortion>> frozenPortionsForLot(String lotId) =>
      freezer.frozenPortionsForLot(lotId);

  /// Moves [grams] of unfrozen coffee from [lotId] into a new frozen portion
  /// and returns its ID. The lot must have a known balance that covers it.
  Future<String> freezeCoffee({
    required String lotId,
    required double grams,
    required String frozenDate,
    String? container,
    String? notes,
  }) => freezer.freezeCoffee(
    lotId: lotId,
    grams: grams,
    frozenDate: frozenDate,
    container: container,
    notes: notes,
  );

  /// Freezes all portions atomically, preserving the original single-portion rules.
  Future<List<String>> freezeCoffeePortions({
    required String lotId,
    required List<double> amounts,
    required String frozenDate,
    String? container,
    String? notes,
  }) => freezer.freezeCoffeePortions(
    lotId: lotId,
    amounts: amounts,
    frozenDate: frozenDate,
    container: container,
    notes: notes,
  );

  /// Returns [grams] of a frozen portion to its lot's unfrozen balance.
  Future<void> thawCoffee(String portionId, double grams) =>
      freezer.thawCoffee(portionId, grams);

  /// Edits a portion. Changing the frozen weight moves the difference between
  /// the portion and its lot, keeping what was already thawed.
  Future<void> updateFrozenPortion({
    required String id,
    required double initialGrams,
    required String frozenDate,
    String? container,
    String? notes,
  }) => freezer.updateFrozenPortion(
    id: id,
    initialGrams: initialGrams,
    frozenDate: frozenDate,
    container: container,
    notes: notes,
  );

  /// Removes a portion recorded by mistake, returning what is still frozen to
  /// the lot's unfrozen balance.
  Future<void> deleteFrozenPortion(String id) =>
      freezer.deleteFrozenPortion(id);
}
