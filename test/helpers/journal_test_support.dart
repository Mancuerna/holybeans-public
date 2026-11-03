import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

/// Sets the grams left in [lot] through the coffee editor, as a user would.
Future<void> setRemainingGrams(
  AppDatabase database,
  JournalRepository repository,
  String coffeeId,
  CoffeeLot lot,
  double grams,
) async {
  final coffee = await (database.select(
    database.coffees,
  )..where((row) => row.id.equals(coffeeId))).getSingle();
  await repository.updateCoffeeProfile(
    id: coffee.id,
    name: coffee.name,
    roaster: coffee.roaster,
    notes: coffee.notes,
    paidPriceCents: coffee.paidPriceCents,
    roastLevel: coffee.roastLevel,
    inventoryLotId: lot.id,
    roastDate: lot.roastDate,
    initialGrams: lot.initialGrams,
    remainingGrams: grams,
    updateRemainingStock: true,
    updateOrigin: false,
  );
}
