part of '../journal_repository.dart';

extension StockReviewOperations on JournalRepository {
  // Explicitly resolves an old archive without guessing whether the user
  // already corrected its returned grams. Transaction makes retries harmless.
  Future<void> resolveBrewStockReview(
    String id, {
    required bool deduct,
  }) => database.transaction(() async {
    final row = await brew(id);
    if (row == null) throw StateError('Brew not found');
    if (row.stockReviewPending != true) return;
    if (deduct) {
      final lot = row.lotId == null ? null : await coffeeLot(row.lotId!);
      if (row.doseGrams == null || lot?.remainingGrams == null) {
        throw StateError('Unknown dose or inventory');
      }
      await _changeBrewStock(row, consume: true);
    } else if (row.frozenPortionId != null) {
      // Accepting a manually corrected balance must still produce a
      // restorable backup: all attributed frozen doses must fit the portion.
      final portion = await _requirePortion(row.frozenPortionId!);
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
          portion.initialGrams + _gramsTolerance) {
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
}
