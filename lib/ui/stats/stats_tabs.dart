import 'package:flutter/material.dart';
import 'package:holybeans/domain/stats_comparison.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';
import 'package:holybeans/ui/stats/stats_consumption.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/stats/stats_widgets.dart';
import 'package:intl/intl.dart';

/// Cups, coffee used, rating and what is left, the cups over time and the
/// daily activity.
class StatsOverviewTab extends StatelessWidget {
  const StatsOverviewTab({super.key, required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final stats = data.stats;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final hasBrews = stats.count > 0;
    final perPeriod = data.perPeriod;
    final periodName = data.period.name;
    return StatsTabList(
      key: const ValueKey('stats-list'),
      children: [
        StatGrid(
          key: const ValueKey('stats-overview'),
          items: [
            StatItem(
              s.statsBrews,
              '${stats.count}',
              caption: _change(s, stats.count, data.previous?.count),
            ),
            if (stats.doseCount > 0)
              StatItem(
                s.statsGround,
                formatGrams(stats.groundGrams, regionalLocale.toString()),
                caption: _change(
                  s,
                  stats.groundGrams,
                  data.previous?.groundGrams,
                ),
              ),
            if (stats.averageDose case final dose?)
              StatItem(
                s.statsAverageDose,
                formatGrams(dose, regionalLocale.toString()),
                caption: _change(s, dose, data.previous?.averageDose),
              ),
            if (stats.brewsPerDay case final perDay? when hasBrews)
              StatItem(
                s.statsBrewsPerDay,
                NumberFormat('0.0#', regionalLocale.toString()).format(perDay),
              ),
            if (stats.averageRating case final rating?)
              StatItem(
                s.statsAverageRatingShort,
                '${number.format(rating)} / 10',
                caption: s.statsRatedCount(stats.ratedCount),
              ),
            StatItem(
              s.statsTotalStock,
              formatGrams(
                data.remainingGrams + data.frozenGrams,
                regionalLocale.toString(),
              ),
              caption: data.frozenGrams > 0
                  ? s.statsFrozenPart(
                      formatGrams(data.frozenGrams, regionalLocale.toString()),
                    )
                  : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            s.statsCurrentInventoryNote,
            key: const ValueKey('stats-inventory-note'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (!hasBrews)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              s.statsNoBrewsInRange,
              key: const ValueKey('stats-empty'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (hasBrews)
          StatsSection(
            title: s.statsBrewsPerPeriod(periodName),
            child: StatsBarChart(
              key: const ValueKey('stats-brews-per-period'),
              summary: s.statsBrewsPerPeriod(periodName),
              valueFormat: (value) => value == 0 ? '' : number.format(value),
              bars: [
                for (final total in perPeriod)
                  (
                    label: statsPeriodLabel(s, total.start, data.period),
                    value: total.value,
                    readout:
                        '${statsPeriodLabel(s, total.start, data.period, long: true)}: '
                        '${s.brewsCount(total.value.round())}',
                  ),
              ],
            ),
          ),
        if (hasBrews) StatsConsumption(data: data),
        StatsSection(
          title: s.statsActivity,
          subtitle: s.statsActivityHint,
          child: ActivityCalendar(
            brews: data.allBrews,
            today: data.now,
            preparedCounts: data.activity,
          ),
        ),
      ],
    );
  }
}

/// How many coffees, roasters and origins, how long after roasting they
/// were first brewed, and the favourite origins, processes, varieties,
/// roasters and best-rated coffees.
class StatsBeansTab extends StatelessWidget {
  const StatsBeansTab({super.key, required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final stats = data.stats;
    final firstCup = data.firstCup;
    return StatsTabList(
      key: const ValueKey('stats-list-beans'),
      children: [
        StatGrid(
          key: const ValueKey('stats-beans-overview'),
          items: [
            StatItem(s.statsBeansTried, '${stats.beansTried}'),
            StatItem(s.statsRoastersTried, '${stats.roastersTried}'),
            StatItem(s.statsOriginsTried, '${stats.originsTried}'),
            if (firstCup != null)
              StatItem(
                s.statsFirstCup,
                s.statsDaysAfterRoast(firstCup.round()),
                caption: s.statsDaysAfterRoastCaption,
              ),
          ],
        ),
        if (stats.count == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(s.statsNoBrewsInRange),
          ),
        for (final (title, key, items) in [
          (s.statsTopOrigins, 'origins', stats.origins),
          (s.statsTopProcesses, 'processes', stats.processes),
          (s.statsTopVarieties, 'varieties', stats.varieties),
          (s.statsTopRoasters, 'roasters', stats.roasters),
        ])
          if (items.isNotEmpty)
            StatsSection(
              title: title,
              child: RankedBars(keyPrefix: key, items: items),
            ),
        if (stats.topRatedBeans.isNotEmpty)
          StatsSection(
            title: s.statsTopRatedBeans,
            subtitle: s.statsTopRatedHint,
            child: RankedBars(
              keyPrefix: 'top-rated',
              items: stats.topRatedBeans,
              byRating: true,
            ),
          ),
      ],
    );
  }
}

/// "+18 % vs previous period", or null when there is nothing to compare.
/// Changes under half a percent read as the same figure and are left out.
String? _change(AppLocalizations s, num current, num? previous) {
  final change = relativeChange(current, previous);
  if (change == null || change.abs() < .005) return null;
  final percent = NumberFormat.percentPattern(regionalLocale.toString())
      .format(change.abs());
  return s.statsChangeVsPrevious('${change > 0 ? '+' : '−'}$percent');
}
