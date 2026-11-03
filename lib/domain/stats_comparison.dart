import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/stats_insights.dart';

/// The period of the same length just before [range] ending at [now]: the
/// brews before the current period starts, and its last day as "now", so
/// [BrewStats.compute] can measure it the same way. Null for all time.
({List<T> brews, DateTime now})? previousPeriod<T>(
  List<T> brews,
  StatsRange range,
  DateTime now, {
  required int Function(T brew) brewedAtMs,
}) {
  final start = rangeStart(range, now);
  if (start == null) return null;
  return (
    brews: [
      for (final brew in brews)
        if (statsDay(DateTime.fromMillisecondsSinceEpoch(brewedAtMs(brew)))
            .isBefore(start))
          brew,
    ],
    now: start.subtract(const Duration(days: 1)),
  );
}

/// How much [current] changed from [previous], as a share: 0.18 is 18 %
/// more. Null when either is unknown or there is nothing to compare with.
double? relativeChange(num? current, num? previous) {
  if (current == null || previous == null || previous == 0) return null;
  return (current - previous) / previous;
}

/// The times of the user's best shots: the middle half (from the first to
/// the third quartile) of the espresso times rated at least [minRating].
/// Null with fewer than [minShots] such shots, so a couple of brews do not
/// draw a range.
({int from, int to})? bestShotTimes(
  Iterable<({int seconds, double? rating})> shots, {
  double minRating = 8,
  int minShots = 5,
}) {
  final times = [
    for (final shot in shots)
      if ((shot.rating ?? -1) >= minRating && shot.seconds > 0) shot.seconds,
  ]..sort();
  if (times.length < minShots) return null;
  int at(double share) {
    final position = (times.length - 1) * share;
    final low = position.floor();
    final high = position.ceil();
    return (times[low] + (times[high] - times[low]) * (position - low)).round();
  }

  return (from: at(.25), to: at(.75));
}
