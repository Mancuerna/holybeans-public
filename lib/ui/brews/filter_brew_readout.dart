import 'package:flutter/material.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// The useful filter measurements below the live weight curve.
class FilterBrewReadout extends StatelessWidget {
  const FilterBrewReadout({
    super.key,
    required this.progress,
    this.showRatio = true,
    this.showTarget = true,
  });

  final FilterBrewProgress progress;
  final bool showRatio;
  final bool showTarget;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    String grams(double? value) =>
        value == null ? '—' : '${number.format(value)} g';
    String ratio(double? value) => value == null
        ? '—'
        : '1:${formatBrewRatioMultiplier(value, regionalLocale.toString())}';
    final excess = progress.excessGrams;
    final values = [
      (s.curveWeight, grams(progress.pouredGrams), 'filter-poured-weight'),
      if (showRatio)
        (
          s.filterCurrentRatio,
          ratio(progress.currentRatio),
          'filter-current-ratio',
        ),
      if (showRatio && showTarget)
        (
          s.filterTargetRatio,
          ratio(progress.targetRatio),
          'filter-target-ratio',
        ),
      if (showTarget)
        (
          excess != null && excess > 0
              ? s.filterWaterOver
              : s.filterWaterRemaining,
          grams(
            excess != null && excess > 0 ? excess : progress.remainingGrams,
          ),
          'filter-water-remaining',
        ),
    ];
    return Column(
      key: const ValueKey('filter-brew-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReadoutLine(values: values.take(showRatio ? 2 : 1).toList()),
        if (showTarget) ...[
          const SizedBox(height: 4),
          _ReadoutLine(values: values.skip(showRatio ? 2 : 1).toList()),
        ],
      ],
    );
  }
}

class _ReadoutLine extends StatelessWidget {
  const _ReadoutLine({required this.values});

  final List<(String, String, String)> values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final (label, value, key) in values)
        _Metric(label: label, value: value, key: ValueKey(key)),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w400,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
