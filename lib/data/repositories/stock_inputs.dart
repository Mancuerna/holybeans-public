import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/stock_inputs.dart';

StockCoffeeFacts stockCoffeeFacts(Coffee row) =>
    (id: row.id, archivedAtMs: row.archivedAtMs);

StockBrewFacts stockBrewFacts(Brew row) => (
  coffeeId: row.coffeeId,
  doseGrams: row.doseGrams,
  brewedAtMs: row.brewedAtMs,
  methodId: row.methodId,
  methodName: row.methodName,
);

StockLotFacts stockLotFacts(CoffeeLot row) => (
  id: row.id,
  coffeeId: row.coffeeId,
  archivedAtMs: row.archivedAtMs,
  initialGrams: row.initialGrams,
  remainingGrams: row.remainingGrams,
  overdrawGrams: row.overdrawGrams,
  roastDate: row.roastDate,
);

StockPortionFacts stockPortionFacts(FrozenPortion row) => (
  id: row.id,
  lotId: row.lotId,
  remainingGrams: row.remainingGrams,
  frozenDate: row.frozenDate,
  label: row.label,
);

StockAdjustmentFacts stockAdjustmentFacts(StockAdjustment row) => (
  lotId: row.lotId,
  previousGrams: row.previousGrams,
  resultingGrams: row.resultingGrams,
  reversedAtMs: row.reversedAtMs,
);
