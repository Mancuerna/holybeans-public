import 'package:flutter/material.dart';
import 'package:holybeans/domain/grinder_consumption.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart' show formatGrams;
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/stats/stats_widgets.dart';
import 'package:intl/intl.dart';

class StatsConsumption extends StatelessWidget {
  const StatsConsumption({super.key, required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    // Grams, like the coffee ground above and every bag.
    final grams = NumberFormat('0', regionalLocale.toString());
    final percent = NumberFormat.percentPattern(regionalLocale.toString());
    final groups = consumptionByGrinder([
      for (final brew in data.stats.brews)
        (
          grinderId: brew.grinderId,
          grinderName: brew.grinderName,
          isPreGround: brew.isPreGround,
          grams: brew.doseGrams,
          brewedAtMs: brew.brewedAtMs,
        ),
    ]);
    final total = groups.fold(0.0, (sum, group) => sum + group.grams);
    final known = groups.fold(0, (sum, group) => sum + group.doseCount);
    final periods = totalsPerPeriod(
      [
        for (final brew in data.stats.brews)
          if (brew.doseGrams case final grams? when grams.isFinite && grams > 0)
            (DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs), grams),
      ],
      data.period,
      now: data.now,
      from: data.from,
    );
    final title = s.statsConsumptionPerPeriod(data.period.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatsSection(
          title: title,
          subtitle: s.statsDoseCoverage(known, data.stats.count),
          child: known == 0
              ? Text(s.statsNoDoses)
              : StatsBarChart(
                  key: const ValueKey('stats-consumption-per-period'),
                  bars: [
                    for (final period in periods)
                      (
                        label: statsPeriodLabel(s, period.start, data.period),
                        value: period.value,
                        readout:
                            '${statsPeriodLabel(s, period.start, data.period, long: true)}: ${formatGrams(period.value, regionalLocale.toString())}',
                      ),
                  ],
                  summary: title,
                  valueFormat: grams.format,
                ),
        ),
        StatsSection(
          title: s.statsConsumptionByGrinder,
          subtitle: s.statsConsumptionHint,
          child: Column(
            key: const ValueKey('stats-grinder-consumption'),
            children: [
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(switch (group.source) {
                        ConsumptionSource.preGround => s.preGround,
                        ConsumptionSource.unknown => s.statsNoGrinder,
                        ConsumptionSource.grinder => group.name ?? s.grinder,
                      }, style: Theme.of(context).textTheme.titleSmall),
                      Wrap(
                        spacing: 12,
                        children: [
                          Text(
                            group.doseCount == 0
                                ? s.statsNoDoses
                                : formatGrams(
                                    group.grams,
                                    regionalLocale.toString(),
                                  ),
                          ),
                          if (total > 0 && group.doseCount > 0)
                            Text(percent.format(group.grams / total)),
                          Text(s.brewsCount(group.brewCount)),
                        ],
                      ),
                      if (group.doseCount < group.brewCount)
                        Text(
                          s.statsDoseCoverage(group.doseCount, group.brewCount),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 6),
                      // Drawn like the ranked bars of methods and origins.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? group.grams / total : 0,
                          minHeight: 4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
