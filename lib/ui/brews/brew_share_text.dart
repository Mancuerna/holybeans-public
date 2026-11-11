import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_ratio.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class BrewShareText {
  static const separator = '- - - - - - -';

  /// "Label: value" lines for the [fields] chosen, coffee first, then the
  /// brew in the order of its details. Unknown values produce no line.
  static String build({
    required AppLocalizations strings,
    required Coffee coffee,
    required List<CoffeeComponent> components,
    required Brew brew,
    required Set<BrewParameter> fields,
    double? cost,
    BrewMethod? method,
    List<String> toolNames = const [],
    String? dateLocaleName,
  }) => formatSections(
    buildSections(
      strings: strings,
      coffee: coffee,
      components: components,
      brew: brew,
      fields: fields,
      cost: cost,
      method: method,
      toolNames: toolNames,
      dateLocaleName: dateLocaleName,
    ),
  );

  static String formatSections(List<List<(String, String)>> sections) =>
      sections
          .map((rows) => rows.map((row) => '${row.$1}: ${row.$2}').join('\n'))
          .join('\n$separator\n');

  /// Field labels and complete values, including multiline pours and notes.
  /// Image sharing reads these directly instead of parsing the formatted text.
  static List<List<(String, String)>> buildSections({
    required AppLocalizations strings,
    required Coffee coffee,
    required List<CoffeeComponent> components,
    required Brew brew,
    required Set<BrewParameter> fields,
    double? cost,
    BrewMethod? method,
    List<String> toolNames = const [],
    String? dateLocaleName,
  }) {
    final beanLines = <(String, String)>[];
    final brewLines = <(String, String)>[];
    void add(List<(String, String)> lines, BrewParameter field, String? value) {
      if (fields.contains(field) && value != null && value.trim().isNotEmpty) {
        lines.add((field.label(strings), value.trim()));
      }
    }

    String number(double value) => formatDecimal(
      value,
      pattern: '0.##',
      locale: regionalLocale.toString(),
    );
    String? grams(double? value) => value == null ? null : '${number(value)} g';
    String? percent(double? value) =>
        value == null ? null : '${number(value)} %';
    String? seconds(int? value) => value == null ? null : '$value s';

    add(beanLines, BrewParameter.coffee, coffee.name);
    add(beanLines, BrewParameter.roaster, coffee.roaster);
    for (final component in components) {
      add(beanLines, BrewParameter.country, component.country);
      add(beanLines, BrewParameter.region, component.region);
      add(beanLines, BrewParameter.variety, component.variety);
      add(beanLines, BrewParameter.process, component.process);
      add(beanLines, BrewParameter.farm, component.farm);
      add(beanLines, BrewParameter.producer, component.producer);
      add(
        beanLines,
        BrewParameter.altitude,
        altitudeLabel(component.altitudeMeters, component.altitudeMaxMeters),
      );
      add(beanLines, BrewParameter.harvest, component.harvest);
    }
    add(
      beanLines,
      BrewParameter.roastLevel,
      coffee.roastLevel == null
          ? null
          : roastLevelLabel(strings, coffee.roastLevel!),
    );
    add(beanLines, BrewParameter.flavorNotes, coffee.flavorProfile);
    add(
      brewLines,
      BrewParameter.cost,
      cost == null ? null : formatEuro(cost, regionalLocale.toString()),
    );
    add(
      brewLines,
      BrewParameter.date,
      DateFormat.yMd(dateLocaleName ?? regionalLocale.toString())
          .addPattern(
            regionalTimeFormat(dateLocaleName ?? regionalLocale.toString())
                .pattern,
          )
          .format(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs)),
    );
    add(brewLines, BrewParameter.method, brew.methodName);

    add(brewLines, BrewParameter.dose, grams(brew.doseGrams));
    add(brewLines, BrewParameter.water, grams(brew.waterGrams));
    add(brewLines, BrewParameter.beverage, grams(brew.beverageGrams));
    add(
      brewLines,
      BrewParameter.ratio,
      formatBrewRatio(
        methodCategory: method?.category,
        methodName: method?.name ?? brew.methodName,
        doseGrams: brew.doseGrams,
        waterGrams: brew.waterGrams,
        beverageGrams: brew.beverageGrams,
        localeName: regionalLocale.toString(),
      ),
    );
    add(
      brewLines,
      BrewParameter.temperature,
      brew.temperatureC == null ? null : '${number(brew.temperatureC!)} °C',
    );

    add(
      brewLines,
      BrewParameter.grinder,
      brew.isPreGround ? strings.preGround : brew.grinderName,
    );
    if (!brew.isPreGround) {
      add(brewLines, BrewParameter.grindSetting, brew.grindSetting);
      add(brewLines, BrewParameter.grindRpm, brew.grindRpm?.toString());
      add(brewLines, BrewParameter.feederRpm, brew.feederRpm?.toString());
    }
    add(brewLines, BrewParameter.tools, toolNames.join(', '));
    add(brewLines, BrewParameter.waterProfile, brew.waterProfileName);
    add(brewLines, BrewParameter.profile, brew.profileName);

    final time = brew.timeSeconds;
    add(
      brewLines,
      BrewParameter.time,
      time == null ? null : formatDuration(time),
    );
    add(brewLines, BrewParameter.preinfusion, seconds(brew.preinfusionSeconds));
    add(brewLines, BrewParameter.firstDrip, seconds(brew.firstDripSeconds));
    add(
      brewLines,
      BrewParameter.pressure,
      brew.pressureBar == null ? null : '${number(brew.pressureBar!)} bar',
    );

    add(brewLines, BrewParameter.bloomCount, brew.bloomCount?.toString());
    add(brewLines, BrewParameter.bloom, seconds(brew.bloomSeconds));
    add(brewLines, BrewParameter.pourCount, brew.pourCount?.toString());
    final phases = BrewPours.fromStorage(
      bloomCount: brew.bloomCount,
      pourCount: brew.pourCount,
      phasesJson: brew.pourPhasesJson,
    ).phases;
    add(
      brewLines,
      BrewParameter.pourDetails,
      phases.isEmpty
          ? null
          : phases
                .map(
                  (phase) => [
                    phase.kind == BrewPourKind.bloom
                        ? strings.bloomNumber(phase.number)
                        : strings.pourNumber(phase.number),
                    if (phase.waterGrams case final grams?)
                      strings.pourWaterValue(number(grams)),
                    if (phase.waterFromPlan) strings.pourWaterFromPlan,
                    if (phase.durationSeconds case final seconds?)
                      strings.pourDurationValue(seconds),
                    if (phase.flowGramsPerSecond case final flow?)
                      strings.pourFlowValue(
                        formatDecimal(
                          flow,
                          pattern: '0.0',
                          locale: regionalLocale.toString(),
                        ),
                      ),
                    if (phase.restSeconds case final seconds?)
                      strings.bloomRestValue(seconds),
                  ].join(' · '),
                )
                .join('\n'),
    );

    add(
      brewLines,
      BrewParameter.tds,
      brew.brix == null
          ? percent(brew.tdsPercent)
          : '≈ ${percent(brew.tdsPercent)} (${brew.brix} °Bx × ${brew.brixFactor})',
    );
    final ey = brewExtractionYield(brew);
    add(
      brewLines,
      BrewParameter.ey,
      ey == null
          ? null
          : '${brew.brix != null ? '≈ ' : ''}${formatDecimal(ey, pattern: '0.#', locale: regionalLocale.toString())} %',
    );
    add(
      brewLines,
      BrewParameter.rating,
      brew.rating == null ? null : '${number(brew.rating!)} / 10',
    );
    add(brewLines, BrewParameter.notes, brew.notes);

    return [
      if (beanLines.isNotEmpty) beanLines,
      if (brewLines.isNotEmpty) brewLines,
    ];
  }
}
