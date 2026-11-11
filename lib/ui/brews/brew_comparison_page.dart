import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_comparison.dart';
import 'package:holybeans/data/repositories/brew_ratio.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_differences_summary.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';
import 'package:holybeans/ui/brews/comparison_values_row.dart';
import 'package:holybeans/ui/brews/espresso_comparison_curves.dart';
import 'package:holybeans/ui/brews/espresso_map_page.dart';
import 'package:holybeans/ui/brews/sensory_map_page.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:intl/intl.dart';

class BrewComparisonPage extends StatefulWidget {
  const BrewComparisonPage({
    super.key,
    required this.a,
    required this.b,
    required this.data,
    required this.actions,
  });
  final Brew a;
  final Brew b;
  final JournalData data;
  final JournalActions actions;

  @override
  State<BrewComparisonPage> createState() => _BrewComparisonPageState();
}

class _BrewComparisonPageState extends State<BrewComparisonPage> {
  late Future<List<ComparisonCurve?>> _curves = _loadCurves();

  Future<List<ComparisonCurve?>> _loadCurves() => Future.wait([
    for (final brew in [widget.a, widget.b]) _loadCurve(brew),
  ]);

  Future<ComparisonCurve?> _loadCurve(Brew brew) async {
    try {
      final row = await widget.actions.repository.brewCurve(brew.id);
      if (row == null || row.curve.isEmpty) return null;
      return ComparisonCurve(
        row.curve,
        row.source == ImportOperations.meticulousSource ? 'ml/s' : 'g/s',
      );
    } catch (error, stack) {
      reportError(error, stack);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final a = widget.a;
    final b = widget.b;
    final rows = _ComparisonRows(s, a, b, widget.actions);
    final comparison = rows.comparison;
    final espresso = rows.espresso;
    final recipeRows = rows.recipe();
    final resultRows = rows.results();
    final tastingRows = rows.tasting();
    String? coffeeName(Brew brew) => widget.data.coffees
        .where((coffee) => coffee.id == brew.coffeeId)
        .firstOrNull
        ?.name;
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('brew-comparison-page'),
      appBar: AppBar(title: Text(espresso ? s.compareShots : s.compareBrews)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (espresso)
            _espressoIdentity(a, b, coffeeName(a), coffeeName(b))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _identity('A', a, coffeeName(a))),
                const SizedBox(width: 8),
                Expanded(child: _identity('B', b, coffeeName(b))),
              ],
            ),
          const SizedBox(height: 12),
          if (a.methodId != b.methodId ||
              comparison.espressoA != comparison.espressoB ||
              a.methodName != b.methodName)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                s.comparisonOtherMethod,
                style: theme.textTheme.bodySmall,
              ),
            ),
          BrewDifferencesSummary(
            comparison: comparison,
            repository: widget.actions.repository,
            hidden: widget.actions.hiddenParameters,
            coffeeA: coffeeName(a),
            coffeeB: coffeeName(b),
          ),
          const SizedBox(height: 12),
          if (espresso) ...[
            _curveSection(s, espresso: true, results: resultRows),
            if (hasSensoryComparison(a, b) &&
                comparison.ratioA != null &&
                comparison.ratioA!.isFinite &&
                comparison.ratioB != null &&
                comparison.ratioB!.isFinite) ...[
              const SizedBox(height: 24),
              Text(s.espressoMap, style: theme.textTheme.titleLarge),
              EspressoMapContent(
                eyPercent: brewExtractionYield(a)!,
                tdsPercent: a.tdsPercent!,
                ratio: comparison.ratioA!,
                other: (
                  eyPercent: brewExtractionYield(b)!,
                  tdsPercent: b.tdsPercent!,
                  ratio: comparison.ratioB!,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ExpansionTile(
              key: const ValueKey('espresso-recipe-tasting'),
              tilePadding: EdgeInsets.zero,
              title: Text(s.comparisonRecipeTasting),
              children: [
                Text(s.recipeSection, style: theme.textTheme.titleSmall),
                _row('', 'A', 'B', header: true),
                ...recipeRows,
                const SizedBox(height: 16),
                Text(s.tasting, style: theme.textTheme.titleSmall),
                ...tastingRows,
              ],
            ),
          ] else ...[
            _row('', 'A', 'B', header: true),
            ...recipeRows,
            ...resultRows.skip(1),
            ...tastingRows,
            const SizedBox(height: 24),
            Text(s.extractionCurve, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _curveSection(s),
            if (hasSensoryComparison(a, b)) ...[
              const SizedBox(height: 24),
              Text(s.sensoryMap, style: theme.textTheme.titleLarge),
              SensoryMapChart(
                eyPercent: brewExtractionYield(a)!,
                tdsPercent: a.tdsPercent!,
                otherEyPercent: brewExtractionYield(b),
                otherTdsPercent: b.tdsPercent,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _curveSection(
    AppLocalizations s, {
    bool espresso = false,
    List<Widget> results = const [],
  }) => FutureBuilder<List<ComparisonCurve?>>(
    future: _curves,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          children: [
            Text(s.comparisonCurveFailed),
            TextButton(
              onPressed: () => setState(() => _curves = _loadCurves()),
              child: Text(s.retry),
            ),
            ...results,
          ],
        );
      }
      if (!snapshot.hasData) {
        return Column(
          children: [
            const Center(child: CircularProgressIndicator()),
            ...results,
          ],
        );
      }
      final [first, second] = snapshot.data!;
      if (!espresso) return ComparisonCurves(a: first, b: second);
      final dripA = widget.a.firstDripSeconds == null
          ? null
          : widget.a.firstDripSeconds! * 1000;
      final dripB = widget.b.firstDripSeconds == null
          ? null
          : widget.b.firstDripSeconds! * 1000;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EspressoComparisonCurves(
            a: first,
            b: second,
            firstDripA: dripA,
            firstDripB: dripB,
            durationA: widget.a.timeSeconds?.toDouble(),
            durationB: widget.b.timeSeconds?.toDouble(),
            beverageA: widget.a.beverageGrams,
            beverageB: widget.b.beverageGrams,
          ),
          const SizedBox(height: 24),
          Text(s.resultSection, style: Theme.of(context).textTheme.titleLarge),
          ...results,
          EspressoCurveSummary(
            a: first,
            b: second,
            firstDripA: dripA,
            firstDripB: dripB,
          ),
        ],
      );
    },
  );

  Widget _espressoIdentity(Brew a, Brew b, String? coffeeA, String? coffeeB) {
    final theme = Theme.of(context);
    final sharedCoffee = coffeeA == coffeeB;
    final sharedMethod = a.methodName == b.methodName;
    Widget shot(String letter, Brew brew, String? coffee) => Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              letter,
              style: theme.textTheme.labelLarge?.copyWith(
                color: letter == 'A'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              [
                if (!sharedCoffee) coffee ?? '—',
                if (!sharedMethod) brew.methodName,
                formatBrewTimestamp(brew, regionalLocale),
              ].join('\n'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sharedCoffee)
          Text(coffeeA ?? '—', style: theme.textTheme.titleMedium),
        if (sharedMethod) Text(a.methodName, style: theme.textTheme.bodySmall),
        shot('A', a, coffeeA),
        shot('B', b, coffeeB),
      ],
    );
  }

  Widget _identity(String letter, Brew brew, String? coffee) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        letter,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: letter == 'A'
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      Text(coffee ?? '—', style: Theme.of(context).textTheme.titleMedium),
      Text(brew.methodName),
      if (brew.doseGrams != null && brew.beverageGrams != null)
        Text(
          '${NumberFormat('0.##', regionalLocale.toString()).format(brew.doseGrams)} g → ${NumberFormat('0.##', regionalLocale.toString()).format(brew.beverageGrams)} g',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      Text(
        formatBrewTimestamp(brew, regionalLocale),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _row(
    String label,
    String? a,
    String? b, {
    String? difference,
    bool header = false,
  }) => ComparisonValuesRow(
    label: label,
    a: a,
    b: b,
    difference: difference,
    header: header,
  );
}

/// The rows of a comparison of [a] and [b]: recipe and equipment, results
/// and tasting, without the parameters the user hides.
class _ComparisonRows {
  _ComparisonRows(this.s, this.a, this.b, this.actions)
    : comparison = BrewComparison(
        a,
        b,
        categoryA: _category(actions, a),
        categoryB: _category(actions, b),
      ),
      number = NumberFormat('0.##', regionalLocale.toString())
        ..turnOffGrouping();

  final AppLocalizations s;
  final Brew a;
  final Brew b;
  final JournalActions actions;
  final BrewComparison comparison;
  final NumberFormat number;

  static String? _category(JournalActions actions, Brew brew) => actions.methods
      .where((method) => method.id == brew.methodId)
      .firstOrNull
      ?.category;

  bool get espresso => comparison.espressoA && comparison.espressoB;

  bool shows(BrewParameter p) => !actions.hiddenParameters.contains(p);

  String value(double? v, String unit) => v == null
      ? s.comparisonMissing
      : '${number.format(v)}${unit.isEmpty ? '' : ' $unit'}';

  String? difference(double? v, String unit) => v == null
      ? null
      : '${s.comparisonDifference}: ${v > 0 ? '+' : ''}${value(v.abs() < .000001 ? 0 : v, unit)}';

  String? ratio(double? multiplier) => multiplier == null
      ? null
      : '1:${formatBrewRatioMultiplier(multiplier, regionalLocale.toString())}';

  String? compass(Brew brew) =>
      brew.tasteBalance == null || brew.tasteStrength == null
      ? null
      : compassLabel(s, brew.tasteBalance!, brew.tasteStrength!);

  static Widget row(
    String label,
    String? a,
    String? b, {
    String? difference,
    bool header = false,
  }) => ComparisonValuesRow(
    label: label,
    a: a,
    b: b,
    difference: difference,
    header: header,
  );

  static const _recipeParameters = {
    BrewParameter.dose,
    BrewParameter.water,
    BrewParameter.temperature,
    BrewParameter.grindRpm,
    BrewParameter.feederRpm,
    BrewParameter.pressure,
    BrewParameter.preinfusion,
    BrewParameter.bloom,
    BrewParameter.bloomCount,
    BrewParameter.pourCount,
  };

  /// Numeric rows; for espresso, split into recipe and results.
  List<Widget> numbers({required bool recipe}) => [
    for (final row in comparison.numbers.where(
      (row) =>
          !espresso ||
          (recipe
              ? _recipeParameters.contains(row.parameter)
              : !_recipeParameters.contains(row.parameter) &&
                    row.parameter != BrewParameter.rating),
    ))
      if (shows(row.parameter) &&
          (espresso && row.parameter == BrewParameter.firstDrip ||
              row.a != null ||
              row.b != null ||
              const {
                BrewParameter.dose,
                BrewParameter.beverage,
                BrewParameter.time,
                BrewParameter.tds,
                BrewParameter.ey,
                BrewParameter.rating,
              }.contains(row.parameter)))
        _ComparisonRows.row(
          row.parameter.label(s),
          row.parameter == BrewParameter.time && row.a != null
              ? formatDuration(row.a!.round())
              : value(row.a, row.unit),
          row.parameter == BrewParameter.time && row.b != null
              ? formatDuration(row.b!.round())
              : value(row.b, row.unit),
          difference: difference(
            row.difference,
            row.parameter == BrewParameter.tds ||
                    row.parameter == BrewParameter.ey
                ? 'pp'
                : row.unit,
          ),
        ),
  ];

  List<Widget> recipe() => [
    if (shows(BrewParameter.grinder))
      row(
        s.grinder,
        a.isPreGround ? s.preGround : a.grinderName,
        b.isPreGround ? s.preGround : b.grinderName,
      ),
    if (shows(BrewParameter.grindSetting))
      row(
        s.grindSetting,
        a.isPreGround ? null : a.grindSetting,
        b.isPreGround ? null : b.grindSetting,
      ),
    if (shows(BrewParameter.waterProfile) &&
        (a.waterProfileName != null || b.waterProfileName != null))
      row(s.waterProfile, a.waterProfileName, b.waterProfileName),
    if (shows(BrewParameter.profile) &&
        (a.profileName != null || b.profileName != null))
      row(s.profileName, a.profileName, b.profileName),
    if (espresso) ...numbers(recipe: true),
  ];

  List<Widget> results() => [
    row('', 'A', 'B', header: true),
    ...numbers(recipe: false),
    if (shows(BrewParameter.ratio))
      row(
        s.ratio,
        ratio(comparison.ratioA),
        ratio(comparison.ratioB),
        difference: difference(comparison.ratioDifference, ''),
      ),
  ];

  List<Widget> tasting() => [
    if (espresso && shows(BrewParameter.rating))
      row(
        s.rating,
        value(a.rating, '/ 10'),
        value(b.rating, '/ 10'),
        difference: difference(
          a.rating == null || b.rating == null ? null : b.rating! - a.rating!,
          '',
        ),
      ),
    if (shows(BrewParameter.rating)) ...[
      if (a.tasteBalance != null ||
          b.tasteBalance != null ||
          a.tasteStrength != null ||
          b.tasteStrength != null)
        row(s.extractionCompass, compass(a), compass(b)),
      for (final score in [
        (s.scoreAcidity, a.acidity, b.acidity),
        (s.scoreSweetness, a.sweetness, b.sweetness),
        (s.scoreBitterness, a.bitterness, b.bitterness),
        (s.scoreBody, a.body, b.body),
        (s.scoreAftertaste, a.aftertaste, b.aftertaste),
      ])
        if (score.$2 != null || score.$3 != null)
          row(
            score.$1,
            value(score.$2?.toDouble(), '/ 5'),
            value(score.$3?.toDouble(), '/ 5'),
            difference: difference(
              score.$2 == null || score.$3 == null
                  ? null
                  : (score.$3! - score.$2!).toDouble(),
              '',
            ),
          ),
    ],
    if (shows(BrewParameter.notes) && (a.notes != null || b.notes != null))
      row(s.notes, a.notes, b.notes),
  ];
}
