import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_csv.dart';
import 'package:holybeans/domain/brew_stats.dart';

String brewsCsv({
  required List<Brew> brews,
  required List<Coffee> coffees,
  required List<CoffeeLot> lots,
}) {
  final coffeeById = {for (final coffee in coffees) coffee.id: coffee};
  final prices = pricePerKgByCoffee(coffees, lots);
  return brewRecordsCsv([
    for (final row in brews)
      (
        acidity: row.acidity,
        aftertaste: row.aftertaste,
        archivedAtMs: row.archivedAtMs,
        beverageGrams: row.beverageGrams,
        bitterness: row.bitterness,
        bloomSeconds: row.bloomSeconds,
        body: row.body,
        brewedAtMs: row.brewedAtMs,
        brix: row.brix,
        brixFactor: row.brixFactor,
        coffeeName: coffeeById[row.coffeeId]?.name,
        cost: brewCost(row, prices),
        doseGrams: row.doseGrams,
        feederRpm: row.feederRpm,
        firstDripSeconds: row.firstDripSeconds,
        grindRpm: row.grindRpm,
        grindSetting: row.grindSetting,
        grinderName: row.grinderName,
        isPreGround: row.isPreGround,
        methodName: row.methodName,
        notes: row.notes,
        preinfusionSeconds: row.preinfusionSeconds,
        pressureBar: row.pressureBar,
        profileName: row.profileName,
        rating: row.rating,
        roastLevel: coffeeById[row.coffeeId]?.roastLevel,
        roaster: coffeeById[row.coffeeId]?.roaster,
        sweetness: row.sweetness,
        tasteBalance: row.tasteBalance,
        tasteStrength: row.tasteStrength,
        tdsPercent: row.tdsPercent,
        temperatureC: row.temperatureC,
        timeSeconds: row.timeSeconds,
        waterGrams: row.waterGrams,
        waterProfileName: row.waterProfileName,
      ),
  ]);
}
