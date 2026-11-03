import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';

extension BrewParameterLabels on BrewParameter {
  String label(AppLocalizations s) => switch (this) {
    BrewParameter.coffee => s.beanName,
    BrewParameter.roaster => s.roaster,
    BrewParameter.country => s.country,
    BrewParameter.region => s.region,
    BrewParameter.variety => s.variety,
    BrewParameter.process => s.process,
    BrewParameter.farm => s.farm,
    BrewParameter.producer => s.producer,
    BrewParameter.altitude => s.altitude,
    BrewParameter.harvest => s.harvest,
    BrewParameter.roastLevel => s.roastLevel,
    BrewParameter.flavorNotes => s.flavorProfile,
    BrewParameter.cost => s.brewCost,
    BrewParameter.date => s.brewDate,
    BrewParameter.method => s.method,
    BrewParameter.dose => s.dose,
    BrewParameter.water => s.water,
    BrewParameter.beverage => s.brewOutput,
    BrewParameter.ratio => s.ratio,
    BrewParameter.temperature => s.temperature,
    BrewParameter.grinder => s.grinder,
    BrewParameter.grindSetting => s.grindSetting,
    BrewParameter.grindRpm => s.grindRpm,
    BrewParameter.feederRpm => s.feederRpm,
    BrewParameter.tools => s.methodTools,
    BrewParameter.waterProfile => s.waterProfile,
    BrewParameter.profile => s.profileName,
    BrewParameter.time => s.extractionDuration,
    BrewParameter.preinfusion => s.preinfusion,
    BrewParameter.firstDrip => s.firstDrip,
    BrewParameter.pressure => s.pressure,
    BrewParameter.bloomCount => s.bloomCount,
    BrewParameter.bloom => s.bloomTime,
    BrewParameter.pourCount => s.pourCount,
    BrewParameter.pourDetails => s.pourDetails,
    BrewParameter.tds => s.tds,
    BrewParameter.ey => s.ey,
    BrewParameter.rating => s.rating,
    BrewParameter.notes => s.notes,
    BrewParameter.photos => s.photos,
  };
}

extension BrewParameterGroupLabels on BrewParameterGroup {
  String label(AppLocalizations s) => switch (this) {
    BrewParameterGroup.coffee => s.parameterGroupCoffee,
    BrewParameterGroup.recipe => s.parameterGroupRecipe,
    BrewParameterGroup.equipment => s.parameterGroupEquipment,
    BrewParameterGroup.timing => s.parameterGroupTiming,
    BrewParameterGroup.pours => s.parameterGroupPours,
    BrewParameterGroup.result => s.parameterGroupResult,
  };
}
