part of '../journal_repository.dart';

/// The steps of [CoffeeOperations.updateCoffeeProfile]: the arguments it
/// accepts, the bag it creates or edits and the single origin it saves.
extension _CoffeeProfileSteps on JournalRepository {
  /// Rejects what the profile editor may not ask for, before any write.
  void _checkProfileEdit({
    required int? paidPriceCents,
    required String? roastLevel,
    required bool checkRoastLevel,
    required int? restDays,
    required bool checkRestDays,
    required int? altitudeMeters,
    required int? altitudeMaxMeters,
    required String? inventoryLotId,
    required bool createInventoryLot,
    required String? roastDate,
    required double? initialGrams,
    required double? remainingGrams,
    required bool updateRemainingStock,
  }) {
    if (createInventoryLot && inventoryLotId != null) {
      throw ArgumentError('A new lot cannot also identify an existing lot');
    }
    _checkPrice(paidPriceCents);
    if (checkRoastLevel) _checkRoastLevel(roastLevel);
    if (checkRestDays) _checkRestDays(restDays);
    if (!validAltitudeRange(altitudeMeters, altitudeMaxMeters)) {
      throw ArgumentError('Invalid altitude range');
    }
    if (inventoryLotId != null || createInventoryLot) {
      _checkDate(roastDate);
      _checkPositive(initialGrams, 'initialGrams');
    } else if (roastDate != null || initialGrams != null) {
      throw ArgumentError('Inventory edits require a selected single lot');
    }
    if (updateRemainingStock && inventoryLotId == null) {
      throw ArgumentError('Current stock edits require a selected single lot');
    }
    if (remainingGrams != null &&
        (!remainingGrams.isFinite || remainingGrams < 0)) {
      throw ArgumentError.value(remainingGrams, 'remainingGrams');
    }
  }

  Future<List<CoffeeLot>> _activeLotsOf(String coffeeId) =>
      (database.select(database.coffeeLots)..where(
            (lot) => lot.coffeeId.equals(coffeeId) & lot.archivedAtMs.isNull(),
          ))
          .get();

  /// The first bag of a coffee that has none active, full.
  Future<void> _createFirstLot(
    String coffeeId, {
    required String? roastDate,
    required double? grams,
  }) async {
    if ((await _activeLotsOf(coffeeId)).isNotEmpty) {
      throw StateError('A coffee without active lots was expected');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database
        .into(database.coffeeLots)
        .insert(
          CoffeeLot(
            id: _uuid.v4(),
            coffeeId: coffeeId,
            roastDate: roastDate,
            initialGrams: grams,
            remainingGrams: grams,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
  }

  /// Edits the only active bag: roast date, quantity bought and, when asked,
  /// the grams left measured by hand.
  Future<void> _editSingleLot(
    String coffeeId,
    String lotId, {
    required String? roastDate,
    required double? initialGrams,
    required double? remainingGrams,
    required bool updateRemainingStock,
  }) async {
    final activeLots = await _activeLotsOf(coffeeId);
    if (activeLots.length != 1 || activeLots.single.id != lotId) {
      throw StateError('Inventory profile editing requires one active lot');
    }
    final lot = activeLots.single;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final quantityChanged = initialGrams != lot.initialGrams;
    if (!quantityChanged &&
        roastDate == lot.roastDate &&
        !updateRemainingStock) {
      return;
    }
    var (nextRemaining, nextOverdraw) = quantityChanged
        ? await _stockAfterPurchaseChange(lot, initialGrams)
        : (lot.remainingGrams, lot.overdrawGrams);
    if (updateRemainingStock && remainingGrams != null) {
      final before = nextRemaining == null
          ? null
          : nextRemaining - (nextOverdraw ?? 0);
      if (before == null || (before - remainingGrams).abs() > _gramsTolerance) {
        await database
            .into(database.stockAdjustments)
            .insert(
              StockAdjustment(
                id: _uuid.v4(),
                operationId: _uuid.v4(),
                coffeeId: coffeeId,
                lotId: lotId,
                reason: 'correction',
                previousGrams: before,
                resultingGrams: remainingGrams,
                createdAtMs: now,
              ),
            );
      }
    }
    if (updateRemainingStock) {
      nextRemaining = remainingGrams;
      nextOverdraw = 0;
    }
    await (database.update(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotId))).write(
      CoffeeLotsCompanion(
        roastDate: Value(roastDate),
        initialGrams: quantityChanged
            ? Value(initialGrams)
            : const Value.absent(),
        remainingGrams: quantityChanged || updateRemainingStock
            ? Value(nextRemaining)
            : const Value.absent(),
        overdrawGrams: quantityChanged || updateRemainingStock
            ? Value(nextOverdraw)
            : const Value.absent(),
        updatedAtMs: Value(now),
      ),
    );
  }

  /// Grams left and overdrawn once the quantity bought of [lot] becomes
  /// [initialGrams].
  Future<(double?, double?)> _stockAfterPurchaseChange(
    CoffeeLot lot,
    double? initialGrams,
  ) async {
    if (initialGrams == null) {
      // Clearing the purchased amount leaves the known physical balance and
      // any overdraw untouched.
      return (lot.remainingGrams, lot.overdrawGrams);
    }
    if (lot.initialGrams == null && lot.remainingGrams != null) {
      // A manual measurement is more useful than deriving stock from a newly
      // entered purchase amount.
      return (lot.remainingGrams, lot.overdrawGrams);
    }
    if (lot.initialGrams != null && lot.remainingGrams != null) {
      // Apply the purchased-quantity change to the signed balance. This also
      // allows correcting the total below brew consumption; the difference
      // is represented as overdraw instead of a negative visible balance.
      return _materializeBalance(
        lot.remainingGrams! -
            (lot.overdrawGrams ?? 0) +
            initialGrams -
            lot.initialGrams!,
      );
    }
    // With no measured balance, derive one only when every active brew has a
    // known dose. Otherwise preserve unknown stock.
    final adjustments = await (database.select(
      database.stockAdjustments,
    )..where((r) => r.lotId.equals(lot.id) & r.reversedAtMs.isNull())).get();
    if (adjustments.isNotEmpty) return (null, null);
    final consumed = await _consumedGrams(lot);
    return consumed == null
        ? (null, null)
        : _materializeBalance(initialGrams - consumed);
  }

  /// Saves the single origin the simple editor shows, creating it when the
  /// coffee had none and something was written.
  Future<void> _saveSingleOrigin(
    String coffeeId, {
    required String? country,
    required String? region,
    required String? farm,
    required String? producer,
    required String? variety,
    required String? process,
    required int? altitudeMeters,
    required int? altitudeMaxMeters,
  }) async {
    final components = await (database.select(
      database.coffeeComponents,
    )..where((row) => row.coffeeId.equals(coffeeId))).get();
    if (components.length > 1) {
      throw StateError('Multi-origin coffee needs a dedicated editor');
    }
    final existing = components.firstOrNull;
    final values =
        [
          country,
          region,
          farm,
          producer,
          variety,
          process,
        ].any((value) => trimOrNull(value) != null) ||
        altitudeMeters != null ||
        altitudeMaxMeters != null;
    if (existing == null && !values) return;
    final component = CoffeeComponent(
      id: existing?.id ?? _uuid.v4(),
      coffeeId: coffeeId,
      position: 0,
      country: trimOrNull(country),
      region: trimOrNull(region),
      farm: trimOrNull(farm),
      producer: trimOrNull(producer),
      variety: trimOrNull(variety),
      process: trimOrNull(process),
      altitudeMeters: altitudeMeters,
      altitudeMaxMeters: altitudeMaxMeters,
      harvest: existing?.harvest,
    );
    if (existing == null) {
      await database.into(database.coffeeComponents).insert(component);
    } else {
      await database.update(database.coffeeComponents).replace(component);
    }
  }
}
