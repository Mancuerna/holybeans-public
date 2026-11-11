part of '../journal_repository.dart';

extension FrozenBrewOperations on JournalRepository {
  /// The current destination of the dose, including a surviving frozen portion.
  Future<BrewStockReturn> brewStockReturn(Brew brew) =>
      stock.brewStockReturn(brew);
}
