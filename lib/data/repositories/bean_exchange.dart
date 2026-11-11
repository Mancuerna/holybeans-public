import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/bean_exchange.dart' as rules;
import 'package:holybeans/domain/bean_exchange.dart' hide existingCoffee;

export 'package:holybeans/domain/bean_exchange.dart' hide existingCoffee;

SharedOrigin sharedOriginFromComponent(CoffeeComponent component) =>
    SharedOrigin(
      country: component.country,
      region: component.region,
      farm: component.farm,
      producer: component.producer,
      variety: component.variety,
      process: component.process,
      altitudeMeters: component.altitudeMeters,
      altitudeMaxMeters: component.altitudeMaxMeters,
      harvest: component.harvest,
    );

SharedBean sharedBeanFromCoffee(
  Coffee coffee,
  List<CoffeeComponent> components,
  List<CoffeeLot> lots,
) => SharedBean.fromFacts(
  (
    name: coffee.name,
    roaster: coffee.roaster,
    roastLevel: coffee.roastLevel,
    isDecaf: coffee.isDecaf,
    flavorProfile: coffee.flavorProfile,
    shopUrl: coffee.shopUrl,
    paidPriceCents: coffee.paidPriceCents,
  ),
  [
    for (final row in components)
      (position: row.position, origin: sharedOriginFromComponent(row)),
  ],
  [
    for (final row in lots)
      (initialGrams: row.initialGrams, createdAtMs: row.createdAtMs),
  ],
);

Coffee? existingCoffee(SharedBean bean, List<Coffee> coffees) {
  final match = rules.existingCoffee(
    bean,
    coffees.map((row) => (id: row.id, name: row.name, roaster: row.roaster)),
  );
  return match == null ? null : coffees.firstWhere((row) => row.id == match.id);
}
