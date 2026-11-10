import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/comparison_values_row.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class BrewDifferencesSummary extends StatefulWidget {
  const BrewDifferencesSummary({
    super.key,
    required this.comparison,
    required this.repository,
    required this.hidden,
    this.coffeeA,
    this.coffeeB,
  });
  final BrewComparison comparison;
  final JournalRepository repository;
  final Set<BrewParameter> hidden;
  final String? coffeeA;
  final String? coffeeB;

  @override
  State<BrewDifferencesSummary> createState() => _BrewDifferencesSummaryState();
}

class _BrewDifferencesSummaryState extends State<BrewDifferencesSummary> {
  late Future<List<String?>> tools = _loadTools();

  Future<List<String?>> _loadTools() async {
    if (widget.hidden.contains(BrewParameter.tools)) return [null, null];
    try {
      final catalog = await widget.repository.toolCatalog();
      final names = <String?>[];
      for (final brew in [widget.comparison.a, widget.comparison.b]) {
        final ids = await widget.repository.brewToolIds(brew.id);
        final values = ids.map((id) => catalog.byId[id]!.name).toList()..sort();
        names.add(values.isEmpty ? null : values.join(', '));
      }
      return names;
    } catch (error, stack) {
      reportError(error, stack);
      rethrow;
    }
  }

  @override
  void didUpdateWidget(covariant BrewDifferencesSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comparison.a.id != widget.comparison.a.id ||
        oldWidget.comparison.b.id != widget.comparison.b.id ||
        oldWidget.repository != widget.repository ||
        oldWidget.hidden.contains(BrewParameter.tools) !=
            widget.hidden.contains(BrewParameter.tools)) {
      tools = _loadTools();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String?>>(
    future: tools,
    builder: (context, snapshot) {
      final s = AppLocalizations.of(context)!;
      final theme = Theme.of(context);
      final rows = widget.comparison
          .differences(
            coffeeA: widget.coffeeA,
            coffeeB: widget.coffeeB,
            preGroundLabel: s.preGround,
            toolsA: snapshot.data?.first,
            toolsB: snapshot.data?.last,
          )
          .where((row) => !widget.hidden.contains(row.parameter))
          .toList();
      final number = NumberFormat('0.##', regionalLocale.toString())
        ..turnOffGrouping();
      String? value(BrewDifference row, Object? v) {
        if (v == null) return null;
        if (v is! num) return v.toString();
        if (row.parameter == BrewParameter.time) {
          return formatDuration(v.round());
        }
        if (row.parameter == BrewParameter.ratio) {
          return '1:${formatBrewRatioMultiplier(v.toDouble(), regionalLocale.toString())}';
        }
        return '${number.format(v)}${row.unit.isEmpty ? '' : ' ${row.unit}'}';
      }

      // A change too small to show ("1:2.5" both times) is not a change.
      final shown = [
        for (final row in rows)
          if (value(row, row.a) != value(row, row.b)) row,
      ];

      return Card(
        key: const ValueKey('brew-differences'),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(s.comparisonChanges),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!snapshot.hasData && !snapshot.hasError)
              const LinearProgressIndicator(),
            if (snapshot.hasError)
              TextButton(
                onPressed: () => setState(() => tools = _loadTools()),
                child: Text(s.comparisonToolsRetry),
              ),
            if (shown.isEmpty && snapshot.hasData) Text(s.comparisonNoChanges),
            for (final result in [false, true])
              if (shown.any((row) => row.result == result)) ...[
                const SizedBox(height: 8),
                Text(
                  result ? s.resultSection : s.comparisonRecipeEquipment,
                  style: theme.textTheme.titleSmall,
                ),
                const ComparisonValuesRow(
                  label: '',
                  a: 'A',
                  b: 'B',
                  header: true,
                ),
                ..._group(
                  context,
                  shown.where((row) => row.result == result).toList(),
                  value,
                ),
              ],
          ],
        ),
      );
    },
  );
}

/// The rows of one part of the differences. A column empty for the whole
/// part says so once, and its cells show a dash instead of repeating
/// "Not recorded"; numeric changes add their difference under the row.
List<Widget> _group(
  BuildContext context,
  List<BrewDifference> rows,
  String? Function(BrewDifference row, Object? v) value,
) {
  final s = AppLocalizations.of(context)!;
  final emptyA = rows.every((row) => row.a == null);
  final emptyB = rows.every((row) => row.b == null);
  String? difference(BrewDifference row) {
    final (a, b) = (row.a, row.b);
    if (a is! num || b is! num || a == b) return null;
    final delta = b - a;
    final shown = value(row, delta.abs());
    if (shown == null) return null;
    // A ratio reads "1:0.3" as a value; its change is the bare figure.
    final figure = row.parameter == BrewParameter.ratio
        ? shown.replaceFirst('1:', '')
        : shown;
    return '${s.comparisonDifference}: ${delta > 0 ? '+' : '−'}$figure';
  }

  return [
    for (final (letter, empty) in [('A', emptyA), ('B', emptyB)])
      if (empty && rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            s.comparisonColumnEmpty(letter),
            key: ValueKey('brew-difference-empty-$letter'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    for (final row in rows)
      ComparisonValuesRow(
        key: ValueKey('brew-difference-${row.parameter.name}'),
        label: row.parameter.label(s),
        a: value(row, row.a),
        b: value(row, row.b),
        missing: emptyA || emptyB ? '—' : null,
        difference: difference(row),
      ),
  ];
}
