import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// What every stats tab reads: the period's figures and the journal they
/// come from.
class StatsData {
  const StatsData({
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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
    children: children,
  );
}
