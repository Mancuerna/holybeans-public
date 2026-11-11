import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_comparison.dart' as rules;

export 'package:holybeans/domain/brew_comparison.dart'
    hide BrewComparison, hasSensoryComparison;

class BrewComparison extends rules.BrewComparison {
  BrewComparison(Brew a, Brew b, {super.categoryA, super.categoryB})
    : super(comparisonBrew(a), comparisonBrew(b));
}

bool hasSensoryComparison(Brew a, Brew b) =>
    rules.hasSensoryComparison(comparisonBrew(a), comparisonBrew(b));

rules.ComparisonBrew comparisonBrew(Brew row) => (
  beverageGrams: row.beverageGrams,
  bloomCount: row.bloomCount,
  bloomSeconds: row.bloomSeconds,
  doseGrams: row.doseGrams,
  feederRpm: row.feederRpm,
  firstDripSeconds: row.firstDripSeconds,
  grindRpm: row.grindRpm,
  grindSetting: row.grindSetting,
  grinderName: row.grinderName,
  id: row.id,
  isPreGround: row.isPreGround,
  methodName: row.methodName,
  pourCount: row.pourCount,
  preinfusionSeconds: row.preinfusionSeconds,
  pressureBar: row.pressureBar,
  profileName: row.profileName,
  rating: row.rating,
  tdsPercent: row.tdsPercent,
  temperatureC: row.temperatureC,
  timeSeconds: row.timeSeconds,
  waterGrams: row.waterGrams,
  waterProfileName: row.waterProfileName,
);
