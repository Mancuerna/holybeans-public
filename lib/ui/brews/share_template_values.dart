import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';

Map<String, String> shareTemplateValues({
  required AppLocalizations strings,
  required Coffee coffee,
  required Brew brew,
  required List<CoffeeComponent> components,
  double? cost,
  BrewMethod? method,
  List<String> toolNames = const [],
  String? dateLocaleName,
}) => {
  for (final entry in shareTemplateTags.entries)
    entry.key: entry.key == 'country_flag'
        ? shareTemplateCountryFlags(components.map((c) => c.country))
        : BrewShareText.buildSections(
            strings: strings,
            coffee: coffee,
            components: components,
            brew: brew,
            cost: cost,
            method: method,
            toolNames: toolNames,
            fields: {entry.value},
            dateLocaleName: dateLocaleName,
          ).expand((rows) => rows).map((row) => row.$2).join(', '),
};

/// Values for showing a template filled in before any brew is chosen: an
/// example brew of [style] with every field a brew of that style records,
/// written exactly as a real brew's would be.
Map<String, String> sampleShareTemplateValues(
  AppLocalizations s,
  ShareTemplateStyle style,
) {
  final espresso = style == ShareTemplateStyle.espresso;
  final now = DateTime.now().millisecondsSinceEpoch;
  final coffee = Coffee(
    id: 'sample',
    name: s.shareTemplateSampleCoffee,
    roaster: s.shareTemplateSampleRoaster,
    roastLevel: espresso ? 'medium' : 'light',
    flavorProfile: s.shareTemplateSampleFlavor,
    isFavorite: false,
    isDecaf: false,
    createdAtMs: now,
    updatedAtMs: now,
  );
  final component = CoffeeComponent(
    id: 'sample',
    coffeeId: 'sample',
    position: 0,
    country: coffeeCountryFor('CO')!.nameFor(s.localeName),
    region: 'Huila',
    farm: s.shareTemplateSampleFarm,
    producer: s.shareTemplateSampleProducer,
    variety: 'Caturra',
    process: s.shareTemplateSampleProcess,
    altitudeMeters: 1700,
    altitudeMaxMeters: 1900,
    harvest: '2025',
  );
  final pours = BrewPours(
    bloomCount: 1,
    pourCount: 2,
    phases: const [
      BrewPourPhase(
        kind: BrewPourKind.bloom,
        number: 1,
        waterGrams: 50,
        durationSeconds: 10,
        restSeconds: 35,
      ),
      BrewPourPhase(
        kind: BrewPourKind.pour,
        number: 1,
        waterGrams: 120,
        durationSeconds: 20,
      ),
      BrewPourPhase(
        kind: BrewPourKind.pour,
        number: 2,
        waterGrams: 118,
        durationSeconds: 25,
      ),
    ],
  );
  final brew = Brew(
    id: 'sample',
    coffeeId: 'sample',
    isPreGround: false,
    methodName: espresso ? s.styleEspresso : 'V60',
    grinderName: s.shareTemplateSampleGrinder,
    grindSetting: espresso ? '2.5' : '24',
    grindRpm: espresso ? 1200 : 900,
    feederRpm: 60,
    doseGrams: 18,
    waterGrams: espresso ? null : 288,
    beverageGrams: espresso ? 36 : 252,
    timeSeconds: espresso ? 28 : 180,
    temperatureC: 93,
    tdsPercent: espresso ? 9.5 : 1.35,
    pressureBar: espresso ? 9 : null,
    preinfusionSeconds: espresso ? 6 : null,
    firstDripSeconds: espresso ? 8 : null,
    profileName: espresso ? s.shareTemplateSampleProfile : null,
    bloomCount: espresso ? null : pours.bloomCount,
    bloomSeconds: espresso ? null : 45,
    pourCount: espresso ? null : pours.pourCount,
    pourPhasesJson: espresso ? null : pours.phasesJson,
    waterProfileName: s.shareTemplateSampleWater,
    rating: 8,
    notes: s.shareTemplateSampleNotes,
    isFavorite: false,
    brewedAtMs: now,
    createdAtMs: now,
    updatedAtMs: now,
  );
  return shareTemplateValues(
    strings: s,
    coffee: coffee,
    brew: brew,
    components: [component],
    cost: espresso ? 0.9 : 0.85,
    toolNames: [
      espresso ? s.shareTemplateSampleBasket : s.shareTemplateSamplePaper,
    ],
  );
}
