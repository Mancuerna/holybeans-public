import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/stats/stats_widgets.dart';
import 'package:intl/intl.dart';

/// What was spent and what the coffee used cost, cost per cup against
/// rating, the best value coffees, spending over time and each roaster's
/// price per kilo.
class StatsCostsTab extends StatelessWidget {
  const StatsCostsTab({super.key, required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final stats = data.stats;
    final euros = euroNumberFormat(regionalLocale.toString());
    final number = NumberFormat('0.#', regionalLocale.toString());
    final from = data.from;
    final bought = purchases(data.lots, data.pricePerKg, from: from);
    final spent = bought.fold<double>(0, (sum, bag) => sum + bag.price);
    final boughtGrams = bought.fold<double>(0, (sum, bag) => sum + bag.grams);
    final values = coffeeValues(stats.brews, data.coffees, data.pricePerKg);
    final rated = [
      for (final value in values)
        if (value.costPerCup != null && value.averageRating != null) value,
    ];
    final best = bestValue(values);
    final roasters = pricePerKgByRoaster(
      data.coffees,
      data.lots,
      data.pricePerKg,
      from: from,
    );
    final spending = totalsPerPeriod(
      [for (final bag in bought) (bag.date, bag.price)],
      data.period,
      now: data.now,
      from: from,
    );
    final periodName = data.period.name;
    String perCup(double? cost) => s.statsCupCost(euros.format(cost ?? 0));
    if (data.pricePerKg.isEmpty) {
      return StatsTabList(
        key: const ValueKey('stats-list-costs'),
        children: [
          Text(
            s.statsNoPrices,
            key: const ValueKey('stats-no-prices'),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      );
    }
    return StatsTabList(
      key: const ValueKey('stats-list-costs'),
      children: [
        StatGrid(
          key: const ValueKey('stats-costs-overview'),
          items: [
            StatItem(
              s.statsSpent,
              euros.format(spent),
              caption: s.statsBags(bought.length),
            ),
            if (boughtGrams > 0)
              StatItem(
                s.statsAveragePricePerKg,
                '${euros.format(spent / boughtGrams * 1000)}/kg',
              ),
            if (stats.costedCount > 0) ...[
              StatItem(
                s.statsCoffeeCost,
                euros.format(stats.coffeeCost),
                caption: s.statsCostCoverage(stats.costedCount),
              ),
              StatItem(s.statsCostPerCup, euros.format(stats.costPerCup)),
            ],
          ],
        ),
        StatsSection(
          title: s.statsCostVsRating,
          subtitle: s.statsCostVsRatingHint,
          child: rated.length < 2
              ? Text(
                  s.statsCostVsRatingFew,
                  key: const ValueKey('stats-cost-vs-rating-few'),
                )
              : StatsScatter(
                  key: const ValueKey('stats-cost-vs-rating'),
                  summary: s.statsCostVsRating,
                  xLabel: s.statsCostAxis,
                  yLabel: s.statsRatingAxis,
                  xFormat: euros.format,
                  yFormat: number.format,
                  // From just under the lowest rating, so close ratings
                  // still spread apart.
                  yMin:
                      rated
                          .map((value) => value.averageRating!)
                          .reduce(math.min)
                          .floorToDouble()
                          .clamp(1, 9) -
                      1,
                  points: [
                    for (final value in rated)
                      (
                        x: value.costPerCup!,
                        y: value.averageRating!,
                        readout:
                            '${value.coffee.name}: '
                            '${perCup(value.costPerCup)}, '
                            '★ ${number.format(value.averageRating)}',
                      ),
                  ],
                ),
        ),
        if (best.isNotEmpty)
          StatsSection(
            title: s.statsBestValue,
            subtitle: s.statsBestValueHint,
            child: _BestValueList(values: best, perCup: perCup),
          ),
        if (spending.where((total) => total.value > 0).length > 1)
          StatsSection(
            title: s.statsSpendingPerPeriod(periodName),
            child: StatsBarChart(
              key: const ValueKey('stats-spending'),
              summary: s.statsSpendingPerPeriod(periodName),
              bars: [
                for (final total in spending)
                  (
                    label: statsPeriodLabel(s, total.start, data.period),
                    value: total.value,
                    readout:
                        '${statsPeriodLabel(s, total.start, data.period, long: true)}: '
                        '${euros.format(total.value)}',
                  ),
              ],
            ),
          ),
        if (roasters.isNotEmpty)
          StatsSection(
            title: s.statsPricePerKgByRoaster,
            subtitle: s.statsPricePerKgByRoasterHint,
            child: _RoasterPriceList(roasters: roasters.take(8).toList()),
          ),
      ],
    );
  }
}

/// The best value coffees: name, roaster, cost per cup and rating.
class _BestValueList extends StatelessWidget {
  const _BestValueList({required this.values, required this.perCup});

  final List<CoffeeValue> values;
  final String Function(double? cost) perCup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    return Column(
      key: const ValueKey('stats-best-value'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, value) in values.indexed)
          Padding(
            key: ValueKey('stats-best-value-$index'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  value.coffee.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Price and rating beside the roaster, or under it when the
                // text is large.
                Wrap(
                  spacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      value.coffee.roaster,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${perCup(value.costPerCup)}, '
                      '★ ${number.format(value.averageRating)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Each roaster's price per kilo and bags, with a bar against the dearest.
class _RoasterPriceList extends StatelessWidget {
  const _RoasterPriceList({required this.roasters});

  /// Dearest first.
  final List<RoasterPrice> roasters;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final euros = euroNumberFormat(regionalLocale.toString());
    return Column(
      key: const ValueKey('stats-roaster-prices'),
      children: [
        for (final (index, roaster) in roasters.indexed)
          Padding(
            key: ValueKey('stats-roaster-price-$index'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      roaster.roaster,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${euros.format(roaster.pricePerKg)}/kg, '
                      '${s.statsBags(roaster.bags)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: roaster.pricePerKg / roasters.first.pricePerKg,
                      minHeight: 4,
                      color: theme.colorScheme.onSurfaceVariant,
                      backgroundColor: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
