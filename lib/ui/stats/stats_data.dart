import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/data/repositories/stats_insights.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/grinder_consumption.dart';
import 'package:holybeans/domain/stats_comparison.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// What every stats tab reads: the period's figures and the journal they
/// come from.
class StatsData {
  StatsData({
    required this.stats,
    required this.range,
    required this.now,
    required this.allBrews,
    required this.coffees,
    required this.lots,
    required this.pricePerKg,
    required this.styleOf,
    required this.remainingGrams,
    required this.frozenGrams,
    this.previous,
  });

  final BrewStats stats;

  /// The same figures for the period of equal length just before; null for
  /// all time.
  final BrewStats? previous;
  final StatsRange range;
  final DateTime now;

  /// Every brew, whatever the period: streaks and the order of each
  /// coffee's brews need them.
  final List<Brew> allBrews;
  final List<Coffee> coffees;
  final List<CoffeeLot> lots;
  final Map<String, double> pricePerKg;
  final BrewStyle Function(Brew brew) styleOf;
  final double remainingGrams;
  final double frozenGrams;

  late final _rangeIds = {for (final brew in stats.brews) brew.id};
  late final _rangeBrews = [
    for (final brew in allBrews)
      if (_rangeIds.contains(brew.id)) brew,
  ];

  late final perPeriod = totalsPerPeriod(
    [
      for (final brew in _rangeBrews)
        (DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs), 1.0),
    ],
    period,
    now: now,
    from: from,
  );
  late final activity = brewsPerDay(allBrews);
  late final firstCup = medianDaysToFirstBrew(allBrews, _rangeBrews, lots);
  late final averages = styleAverages(_rangeBrews, styleOf);
  late final espressoHistogram = histogram([
    for (final seconds in averages[BrewStyle.espresso]?.times ?? const <int>[])
      if (seconds <= 120) seconds,
  ], 5);
  late final filterHistogram = histogram([
    for (final seconds in averages[BrewStyle.filter]?.times ?? const <int>[])
      if (seconds <= 1200) seconds,
  ], 30);
  // The user's own reference: where their well-rated shots land.
  late final bestEspressoTimes = espressoHistogram.length < 2
      ? null
      : bestShotTimes([
          for (final brew in _rangeBrews)
            if (styleOf(brew) == BrewStyle.espresso)
              if (brew.timeSeconds case final seconds? when seconds <= 120)
                (seconds: seconds, rating: brew.rating),
        ]);
  late final learning = learningCurve(allBrews, _rangeBrews);
  late final temperatures = ratingByTemperature(_rangeBrews);
  late final bought = purchases(lots, pricePerKg, from: from);
  late final values = coffeeValues(_rangeBrews, coffees, pricePerKg);
  late final spent = bought.fold<double>(0, (sum, bag) => sum + bag.price);
  late final boughtGrams = bought.fold<double>(
    0,
    (sum, bag) => sum + bag.grams,
  );
  late final ratedValues = [
    for (final value in values)
      if (value.costPerCup != null && value.averageRating != null) value,
  ];
  late final bestValues = bestValue(values);
  late final costRatingMinimum = ratedValues.isEmpty
      ? null
      : ratedValues.map((value) => value.averageRating!).reduce(math.min);
  late final roasterPrices = pricePerKgByRoaster(
    coffees,
    lots,
    pricePerKg,
    from: from,
  );
  late final spending = totalsPerPeriod(
    [for (final bag in bought) (bag.date, bag.price)],
    period,
    now: now,
    from: from,
  );
  late final spendingPeriods = spending
      .where((total) => total.value > 0)
      .length;
  late final consumption = consumptionByGrinder([
    for (final brew in _rangeBrews)
      (
        grinderId: brew.grinderId,
        grinderName: brew.grinderName,
        isPreGround: brew.isPreGround,
        grams: brew.doseGrams,
        brewedAtMs: brew.brewedAtMs,
      ),
  ]);
  late final consumedPeriods = totalsPerPeriod(
    [
      for (final brew in _rangeBrews)
        if (brew.doseGrams case final grams? when grams.isFinite && grams > 0)
          (DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs), grams),
    ],
    period,
    now: now,
    from: from,
  );

  /// Force lazy calculations on the worker before publishing the snapshot.
  List<Object?> prepareInsights() => [
    perPeriod,
    activity,
    firstCup,
    averages,
    espressoHistogram,
    filterHistogram,
    bestEspressoTimes,
    learning,
    temperatures,
    bought,
    values,
    spent,
    boughtGrams,
    ratedValues,
    bestValues,
    costRatingMinimum,
    roasterPrices,
    spending,
    spendingPeriods,
    consumption,
    consumedPeriods,
  ];

  StatsPeriod get period => periodFor(range);

  /// The first day of the period; null for all time.
  DateTime? get from => rangeStart(range, now);
}

/// The name of [period] as the bars over time show it, and as read aloud.
String statsPeriodLabel(
  AppLocalizations s,
  DateTime start,
  StatsPeriod period, {
  bool long = false,
}) => switch (period) {
  StatsPeriod.day =>
    (long
            ? DateFormat.MMMEd(regionalLocale.toString())
            : DateFormat.E(regionalLocale.toString()))
        .format(start),
  StatsPeriod.week =>
    long
        ? s.statsWeekOf(
            DateFormat.MMMd(regionalLocale.toString()).format(start),
          )
        : DateFormat.MMMd(regionalLocale.toString()).format(start),
  StatsPeriod.month =>
    (long
            ? DateFormat.yMMMM(regionalLocale.toString())
            : DateFormat.MMM(regionalLocale.toString()))
        .format(start),
};

/// The tab's sections, scrolling, with room at the end.
class StatsTabList extends StatelessWidget {
  const StatsTabList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: children.length,
    itemBuilder: (_, index) => children[index],
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
  );
}
