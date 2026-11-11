part of '../journal_repository.dart';

extension StockReviewOperations on JournalRepository {
  Future<void> resolveBrewStockReview(String id, {required bool deduct}) =>
      stock.resolveBrewStockReview(id, deduct: deduct);
}
