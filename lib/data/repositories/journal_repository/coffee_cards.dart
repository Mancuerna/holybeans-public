part of '../journal_repository.dart';

extension CoffeeCards on JournalRepository {
  /// Adds the coffee a card describes, with its bag, as a new coffee;
  /// returns its ID.
  Future<String> createCoffeeFromCard(SharedBean bean) =>
      coffees.createCoffeeFromCard(bean);

  /// Whether the coffee is decaf, and its shop page; blank clears it.
  Future<void> setCoffeeExtras(
    String id, {
    required bool isDecaf,
    String? shopUrl,
  }) => coffees.setCoffeeExtras(id, isDecaf: isDecaf, shopUrl: shopUrl);
}
