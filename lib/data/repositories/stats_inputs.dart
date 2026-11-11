import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_inputs.dart';

StatsBrew statsBrew(Brew row, {BrewStyle style = BrewStyle.filter}) => (
  id: row.id,
  coffeeId: row.coffeeId,
  lotId: row.lotId,
  methodName: row.methodName,
  brewedAtMs: row.brewedAtMs,
  createdAtMs: row.createdAtMs,
  doseGrams: row.doseGrams,
  rating: row.rating,
  tasteBalance: row.tasteBalance,
  tasteStrength: row.tasteStrength,
  temperatureC: row.temperatureC,
  beverageGrams: row.beverageGrams,
  waterGrams: row.waterGrams,
  timeSeconds: row.timeSeconds,
  style: style,
);

StatsCoffee statsCoffee(Coffee row) => (
  id: row.id,
  name: row.name,
  roaster: row.roaster,
  paidPriceCents: row.paidPriceCents,
);

StatsLot statsLot(CoffeeLot row) => (
  id: row.id,
  coffeeId: row.coffeeId,
  initialGrams: row.initialGrams,
  purchaseDate: row.purchaseDate,
  roastDate: row.roastDate,
  createdAtMs: row.createdAtMs,
);

StatsComponent statsComponent(CoffeeComponent row) => (
  coffeeId: row.coffeeId,
  process: row.process,
  variety: row.variety,
  country: row.country,
);
