part of '../journal_repository.dart';

extension CoffeeCards on JournalRepository {
  /// Adds the coffee a card describes, with its bag, as a new coffee;
  /// returns its ID.
  Future<String> createCoffeeFromCard(SharedBean bean) =>
      database.transaction(() async {
        final id = await createCoffeeWithComponents(
          name: bean.name,
          roaster: bean.roaster,
          components: [
            for (final origin in bean.origins)
              CoffeeComponentInput(
                country: origin.country,
                region: origin.region,
                farm: origin.farm,
                producer: origin.producer,
                variety: origin.variety,
                process: origin.process,
                altitudeMeters: origin.altitudeMeters,
                altitudeMaxMeters: origin.altitudeMaxMeters,
                harvest: origin.harvest,
              ),
          ],
          roastDate: bean.roastDate,
          initialGrams: bean.bagGrams,
          paidPriceCents: bean.priceCents,
          roastLevel: bean.roastLevel,
          flavorProfile: bean.flavorProfile,
        );
        await setCoffeeExtras(id, isDecaf: bean.decaf, shopUrl: bean.shopUrl);
        return id;
      });

  /// Whether the coffee is decaf, and its shop page; blank clears it.
  Future<void> setCoffeeExtras(
    String id, {
    required bool isDecaf,
    String? shopUrl,
  }) async {
    final String? link;
    try {
      link = normalizeWebLink(shopUrl);
    } on FormatException {
      throw ArgumentError.value(shopUrl, 'shopUrl');
    }
    final updated =
        await (database.update(
          database.coffees,
        )..where((coffee) => coffee.id.equals(id))).write(
          CoffeesCompanion(isDecaf: Value(isDecaf), shopUrl: Value(link)),
        );
    if (updated == 0) throw StateError('Coffee not found');
  }
}
