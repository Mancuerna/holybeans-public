import 'dart:math';

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/frozen_brew.dart';

/// Inventory movements and the stock reviews caused by recorded brews.
class BrewStockLedger {
  BrewStockLedger(this.database, this._freezer, this._records);
  final AppDatabase database;
  final FreezerRepository _freezer;
  final JournalRecordQueries _records;

  /// Fresh stock and dose history after saving; reads do not depend on streams
  /// having delivered the transaction yet.
  Future<StockArchiveSuggestion?> archiveSuggestionForBrew(String brewId) =>
      database.transaction(() async {
        final savedBrew = await _records.brew(brewId);
        if (savedBrew == null) return null;
        final savedCoffee = await _records.coffee(savedBrew.coffeeId);
        if (savedCoffee == null) return null;
        return stockArchiveSuggestion(
          coffee: savedCoffee,
          brew: savedBrew,
          history: await _records.brewsOfCoffee(savedCoffee.id),
          lots: await _records.coffeeLots(savedCoffee.id),
          portions: await database.select(database.frozenPortions).get(),
        );
      });

  Future<void> resolveBrewStockReview(
    String id, {
    required bool deduct,
  }) => database.transaction(() async {
    final row = await _records.brew(id);
    if (row == null) throw StateError('Brew not found');
    if (row.stockReviewPending != true) return;
    if (deduct) {
      final lot = row.lotId == null
          ? null
          : await _records.coffeeLot(row.lotId!);
      if (row.doseGrams == null || lot?.remainingGrams == null) {
        throw StateError('Unknown dose or inventory');
      }
      await changeBrewStock(row, consume: true);
    } else if (row.frozenPortionId != null) {
      // Accepting a manually corrected balance must still produce a
      // restorable backup: all attributed frozen doses must fit the portion.
      final portion = await _freezer.requirePortion(row.frozenPortionId!);
      final attributed =
          await (database.select(database.brews)..where(
                (b) =>
                    b.frozenPortionId.equals(portion.id) &
                    (b.stockReviewPending.isNull() |
                        b.stockReviewPending.equals(false)),
              ))
              .get();
      final used = attributed.fold<double>(
        row.frozenDoseGrams ?? 0,
        (sum, b) => sum + (b.frozenDoseGrams ?? 0),
      );
      if (used + portion.remainingGrams >
          portion.initialGrams + stockTolerance) {
        throw StateError('Frozen balance does not include this dose');
      }
    }
    await (database.update(
      database.brews,
    )..where((b) => b.id.equals(id))).write(
      BrewsCompanion(
        stockReviewPending: const Value(false),
        updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      ),
    );
  });

  /// Returns the signed balance across known active lots, or null if any lot
  /// has unknown stock (or no active inventory has been recorded).
  Future<double?> coffeeStockBalance(String coffeeId) async {
    return coffeeStockBalanceForActiveLots(coffeeId);
  }

  Future<double?> coffeeStockBalanceForActiveLots(String coffeeId) async {
    final lots = await _records.coffeeLots(coffeeId);
    if (lots.isEmpty || lots.any((lot) => lot.remainingGrams == null)) {
      return null;
    }
    return lots.fold<double>(
      0,
      (sum, lot) => sum + lot.remainingGrams! - (lot.overdrawGrams ?? 0),
    );
  }

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

  Future<({String? portionId, double? grams})> saveBrewStock(
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
      final portion = await _freezer.requirePortion(frozenSource.portionId);
      if (portion.lotId != lotId || frozenSource.lotId != lotId) {
        throw ArgumentError('Frozen portion does not belong to selected lot');
      }
      // Saving and thawing share the outer brew transaction. Cancellation,
      // validation errors and failed inserts leave the freezer unchanged.
      await _freezer.thawCoffee(portion.id, frozenSource.grams);
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
    if (previous != null && brewAdjustsStock(previous)) {
      final origin = await brewStockReturn(previous);
      if (origin.frozenGrams > 0) {
        frozenChanges[previous.frozenPortionId!] = origin.frozenGrams;
      }
    }
    if (frozenSource == null &&
        portionId != null &&
        (previous == null || brewAdjustsStock(previous))) {
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

  Future<void> changeBrewStock(Brew brew, {required bool consume}) async {
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
      if (entry.value.abs() < stockTolerance) continue;
      final portion = await _freezer.requirePortion(entry.key);
      final left = roundStockGrams(portion.remainingGrams + entry.value);
      if (left < -stockTolerance ||
          left > portion.initialGrams + stockTolerance) {
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

  /// Grams each lot gets back or gives when a brew is saved: a counted
  /// [previous] version returns its dose, and the new one takes [doseGrams]
  /// from [lotId]. Legacy brews awaiting stock review draw nothing.
  Map<String, double> _doseChanges(
    Brew? previous, {
    required String? lotId,
    required double? doseGrams,
  }) {
    final changes = <String, double>{};
    if (previous != null &&
        brewAdjustsStock(previous) &&
        previous.lotId != null &&
        previous.doseGrams != null) {
      changes.update(
        previous.lotId!,
        (value) => value + previous.doseGrams!,
        ifAbsent: () => previous.doseGrams!,
      );
    }
    if ((previous == null || brewAdjustsStock(previous)) &&
        lotId != null &&
        doseGrams != null) {
      changes.update(
        lotId,
        (value) => value - doseGrams,
        ifAbsent: () => -doseGrams,
      );
    }
    return changes;
  }

  Future<void> _applyStockChanges(Map<String, double> changes) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final entry in changes.entries) {
      if (entry.value == 0) continue;
      final lot = await (database.select(
        database.coffeeLots,
      )..where((row) => row.id.equals(entry.key))).getSingleOrNull();
      if (lot == null) throw StateError('Lot not found');
      final remaining = lot.remainingGrams;
      if (remaining == null) continue;
      final (nextRemaining, nextOverdraw) = materializeBalance(
        remaining - (lot.overdrawGrams ?? 0) + entry.value,
      );
      await (database.update(
        database.coffeeLots,
      )..where((row) => row.id.equals(entry.key))).write(
        CoffeeLotsCompanion(
          remainingGrams: Value(nextRemaining),
          overdrawGrams: Value(nextOverdraw),
          updatedAtMs: Value(now),
        ),
      );
    }
  }

  Future<double?> consumedGrams(CoffeeLot lot) async {
    final activeBrews =
        await (database.select(database.brews)..where(
              (brew) =>
                  brew.lotId.equals(lot.id) &
                  (brew.stockReviewPending.isNull() |
                      brew.stockReviewPending.equals(false)),
            ))
            .get();
    var consumed = 0.0;
    for (final brew in activeBrews) {
      final dose = brew.doseGrams;
      if (dose == null || !dose.isFinite || dose < 0) {
        return null;
      }
      consumed += dose;
    }
    return consumed;
  }
}
