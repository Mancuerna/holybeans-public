part of '../journal_repository.dart';

extension StockAdjustmentOperations on JournalRepository {
  Stream<List<StockAdjustment>> watchStockAdjustments({
    String? coffeeId,
    bool activeOnly = false,
  }) => stockEdits.watchStockAdjustments(
    coffeeId: coffeeId,
    activeOnly: activeOnly,
  );
  Future<List<StockAdjustment>> stockAdjustments(String coffeeId) =>
      stockEdits.stockAdjustments(coffeeId);
  Future<String> adjustStock({
    required String coffeeId,
    required String reason,
    required double grams,
    String? frozenPortionId,
    String? notes,
  }) => stockEdits.adjustStock(
    coffeeId: coffeeId,
    reason: reason,
    grams: grams,
    frozenPortionId: frozenPortionId,
    notes: notes,
  );
  Future<void> undoStockAdjustment(String operationId) =>
      stockEdits.undoStockAdjustment(operationId);
}
