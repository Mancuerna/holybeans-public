part of '../journal_repository.dart';

bool _brewAdjustsStock(Brew brew) => brew.stockReviewPending != true;

/// Stock adjustments keep each thaw's origin while leaving other uses alone.
extension FrozenBrewOperations on JournalRepository {
  /// The current destination of the dose, including a surviving frozen portion.
  Future<BrewStockReturn> brewStockReturn(Brew brew) async {
    final dose = brew.lotId == null ? 0.0 : brew.doseGrams ?? 0.0;
    final portionId = brew.frozenPortionId;
    final portion = portionId == null
        ? null
        : await (database.select(
            database.frozenPortions,
          )..where((row) => row.id.equals(portionId))).getSingleOrNull();
    final frozen = portion?.lotId == brew.lotId && portion != null
        ? (brew.frozenDoseGrams ?? 0).clamp(0.0, dose)
        : 0.0;
    return BrewStockReturn(
      availableGrams: dose - frozen,
      frozenGrams: frozen,
      portionLabel: frozen > 0 ? portion?.label : null,
    );
  }

  Future<({String? portionId, double? grams})> _saveBrewStock(
    Brew? previous, {
    required String? lotId,
    required double? doseGrams,
    required FrozenBrewSource? frozenSource,
  }) async {
    if (previous?.archivedByCoffee == true &&
        previous?.frozenPortionId != null &&
        (previous!.lotId != lotId || previous.doseGrams != doseGrams)) {
      throw const BrewArchivedWithCoffeeException();
    }
    String? portionId;
    double? frozenGrams;
    if (frozenSource != null) {
      if (previous != null || lotId == null || doseGrams == null) {
        throw ArgumentError('A frozen source needs a new brew, lot and dose');
      }
      final portion = await _requirePortion(frozenSource.portionId);
      if (portion.lotId != lotId || frozenSource.lotId != lotId) {
        throw ArgumentError('Frozen portion does not belong to selected lot');
      }
      // Saving and thawing share the outer brew transaction. Cancellation,
      // validation errors and failed inserts leave the freezer unchanged.
      await thawCoffee(portion.id, frozenSource.grams);
      portionId = portion.id;
      frozenGrams = min(doseGrams, frozenSource.grams);
    } else if (previous != null && previous.lotId == lotId) {
      final origin = await brewStockReturn(previous);
      final retained = min(doseGrams ?? 0, origin.frozenGrams);
      if (retained > 0) {
        portionId = previous.frozenPortionId;
        frozenGrams = retained;
      }
    }

    final changes = _doseChanges(previous, lotId: lotId, doseGrams: doseGrams);
    final frozenChanges = <String, double>{};
    if (previous != null && _brewAdjustsStock(previous)) {
      final origin = await brewStockReturn(previous);
      if (origin.frozenGrams > 0) {
        frozenChanges[previous.frozenPortionId!] = origin.frozenGrams;
      }
    }
    if (frozenSource == null &&
        portionId != null &&
        (previous == null || _brewAdjustsStock(previous))) {
      frozenChanges.update(
        portionId,
        (grams) => grams - frozenGrams!,
        ifAbsent: () => -frozenGrams!,
      );
    }
    await _adjustFrozenStock(frozenChanges, changes);
    await _applyStockChanges(changes);
    return (portionId: portionId, grams: frozenGrams);
  }

  Future<void> _changeBrewStock(Brew brew, {required bool consume}) async {
    if (brew.lotId == null || brew.doseGrams == null) return;
    final origin = await brewStockReturn(brew);
    final changes = {brew.lotId!: consume ? -brew.doseGrams! : brew.doseGrams!};
    if (origin.frozenGrams > 0) {
      await _adjustFrozenStock({
        brew.frozenPortionId!: consume
            ? -origin.frozenGrams
            : origin.frozenGrams,
      }, changes);
    }
    await _applyStockChanges(changes);
  }

  Future<void> _adjustFrozenStock(
    Map<String, double> portions,
    Map<String, double> lots,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in portions.entries) {
      if (entry.value.abs() < _gramsTolerance) continue;
      final portion = await _requirePortion(entry.key);
      final left = _roundGrams(portion.remainingGrams + entry.value);
      if (left < -_gramsTolerance ||
          left > portion.initialGrams + _gramsTolerance) {
        throw StateError('Frozen portion cannot cover this stock adjustment');
      }
      await (database.update(
        database.frozenPortions,
      )..where((row) => row.id.equals(portion.id))).write(
        FrozenPortionsCompanion(
          remainingGrams: Value(left.clamp(0.0, portion.initialGrams)),
          thawedAtMs: Value(left <= 0 ? (portion.thawedAtMs ?? now) : null),
          updatedAtMs: Value(now),
        ),
      );
      lots.update(
        portion.lotId,
        (grams) => grams - entry.value,
        ifAbsent: () => -entry.value,
      );
    }
  }
}
