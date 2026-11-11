import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/stats_insights.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/stats/stats_widgets.dart';
import 'package:intl/intl.dart';

/// "3:05" for [seconds].
String _minutes(num seconds) {
  final whole = seconds.round();
  return formatDuration(whole);
}

/// Ratios and times, the methods, the rating by style, the extraction map,
/// how long shots and filters take, how a coffee is dialled in and the
/// rating by temperature.
class StatsBrewsTab extends StatelessWidget {
  const StatsBrewsTab({super.key, required this.data});

  final StatsData data;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final stats = data.stats;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final averages = data.averages;
    final espresso = averages[BrewStyle.espresso];
    final filter = averages[BrewStyle.filter];
    final curve = data.learning;
    final byTemperature = data.temperatures;
    String rated(String label, RatedGroup group) =>
        '$label: ${number.format(group.averageRating)} / 10, '
        '${s.statsRatedCount(group.count)}';
    return StatsTabList(
      key: const ValueKey('stats-list-brews'),
      children: [
        _TypicalFigures(filter: filter, espresso: espresso),
        if (stats.count == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(s.statsNoBrewsInRange),
          ),
        if (stats.methods.isNotEmpty)
          StatsSection(
            title: s.statsTopMethods,
            child: RankedBars(keyPrefix: 'methods', items: stats.methods),
          ),
        if (stats.ratingByStyle.isNotEmpty)
          StatsSection(
            title: s.statsRatingByStyle,
            child: StatGrid(
              key: const ValueKey('stats-rating-by-style'),
              items: [
                for (final style in BrewStyle.values)
                  if (stats.ratingByStyle[style] case final item?)
                    StatItem(
                      brewStyleLabel(s, style),
                      '${number.format(item.averageRating)} / 10',
                      caption: s.statsRatedCount(item.count),
                    ),
              ],
            ),
          ),
        if (stats.compass.isNotEmpty)
          StatsSection(
            title: s.statsExtraction,
            subtitle: s.statsExtractionHint,
            child: ExtractionMapGrid(cells: stats.compass),
          ),
        ?_shotTimes(s),
        ?_filterTimes(s),
        if (curve.length > 1)
          StatsSection(
            title: s.statsLearningCurve,
            subtitle: s.statsLearningCurveHint,
            child: StatsBarChart(
              key: const ValueKey('stats-learning-curve'),
              valueFormat: number.format,
              summary: s.statsLearningCurve,
              maxValue: 10,
              bars: [
                for (final MapEntry(key: brew, value: group) in curve.entries)
                  (
                    label: brew == 8 ? '8+' : s.statsBrewNumber('$brew'),
                    value: group.averageRating,
                    readout: rated(
                      brew == 8 ? '8+' : s.statsBrewNumber('$brew'),
                      group,
                    ),
                  ),
              ],
            ),
          ),
        if (byTemperature.length > 1)
          StatsSection(
            title: s.statsRatingByTemperature,
            subtitle: s.statsRatingByTemperatureHint,
            child: StatsBarChart(
              key: const ValueKey('stats-rating-by-temperature'),
              valueFormat: number.format,
              summary: s.statsRatingByTemperature,
              maxValue: 10,
              bars: [
                for (final MapEntry(key: from, value: group)
                    in byTemperature.entries)
                  (
                    label: '$from°',
                    value: group.averageRating,
                    readout: rated('$from–${from + 1} °C', group),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// How long shots take, with the band where the well-rated ones land;
  /// null with too few to draw. Shots over two minutes are typos or a timer
  /// left running and would stretch the chart.
  StatsSection? _shotTimes(AppLocalizations s) {
    final shots = data.espressoHistogram;
    if (shots.length < 2) return null;
    final best = data.bestEspressoTimes;
    return StatsSection(
      title: s.statsShotTimes,
      subtitle: best == null
          ? s.statsShotTimesHint
          : '${s.statsShotTimesHint} '
                '${s.statsBestShotsBand(best.from, best.to)}',
      child: StatsBarChart(
        key: const ValueKey('stats-shot-times'),
        summary: s.statsShotTimes,
        marked: {
          if (best != null)
            for (final (index, bucket) in shots.indexed)
              if (bucket.from <= best.to && bucket.from + 4 >= best.from) index,
        },
        bars: [
          for (final bucket in shots)
            (
              label: '${bucket.from}',
              value: bucket.count.toDouble(),
              readout:
                  '${bucket.from}–${bucket.from + 4} s: '
                  '${s.brewsCount(bucket.count)}',
            ),
        ],
      ),
    );
  }

  /// How long filters take, in half minutes; null with too few to draw.
  /// Filters over twenty minutes are left out, like long shots.
  StatsSection? _filterTimes(AppLocalizations s) {
    final filters = data.filterHistogram;
    if (filters.length < 2) return null;
    return StatsSection(
      title: s.statsFilterTimes,
      subtitle: s.statsFilterTimesHint,
      child: StatsBarChart(
        key: const ValueKey('stats-filter-times'),
        summary: s.statsFilterTimes,
        bars: [
          for (final bucket in filters)
            (
              label: _minutes(bucket.from),
              value: bucket.count.toDouble(),
              readout:
                  '${_minutes(bucket.from)}–${_minutes(bucket.from + 29)}: '
                  '${s.brewsCount(bucket.count)}',
            ),
        ],
      ),
    );
  }
}

/// Typical ratio and time of filter and espresso, as medians.
class _TypicalFigures extends StatelessWidget {
  const _TypicalFigures({required this.filter, required this.espresso});

  final StyleAverages? filter;
  final StyleAverages? espresso;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    // Two columns, so each style keeps its own row: filter, then espresso.
    return StatGrid(
      key: const ValueKey('stats-brews-overview'),
      minimumTileWidth: double.infinity,
      items: [
        if (filter?.ratio case final ratio?)
          StatItem(
            s.statsFilterRatio,
            '1:${number.format(ratio)}',
            caption: s.statsMedian,
          ),
        if (filter?.timeSeconds case final seconds?)
          StatItem(
            s.statsFilterTime,
            _minutes(seconds),
            caption: s.statsMedian,
          ),
        if (espresso?.ratio case final ratio?)
          StatItem(
            s.statsEspressoRatio,
            '1:${number.format(ratio)}',
            caption: s.statsMedian,
          ),
        if (espresso?.timeSeconds case final seconds?)
          StatItem(s.statsShotTime, _minutes(seconds), caption: s.statsMedian),
      ],
    );
  }
}
