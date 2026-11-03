/// Freshness of roasted coffee, modelled on how much CO₂ the beans have
/// already released, plus a personal "sweet spot" learned from ratings.
///
/// Whole beans release the CO₂ formed during roasting following a Weibull
/// curve, M(t) = M∞·(1 − e^−(t/λ)^k), and darker roasts release it faster
/// (Smrke et al., J. Agric. Food Chem. 2018, doi:10.1021/acs.jafc.7b03310).
/// Brewing is uneven while a lot of gas remains, and once most of it is gone
/// the beans lose their protective atmosphere and aromas oxidise. Each phase
/// therefore starts when a given share of the gas has been released; the
/// share is higher for espresso, which reacts more to leftover gas. See
/// docs/DATA.md for the sources and how the thresholds were chosen.
library;

import 'dart:math' as math;

enum BrewStyle { espresso, filter }

enum FreshnessPhase { degassing, prime, good, aging, stale }

/// The phase a coffee is in today and the brew style it was judged for.
typedef FreshnessToday = ({
  FreshnessPhase phase,
  BrewStyle style,

  /// Effective days since roasting, and that style's window.
  int day,
  FreshnessWindow window,
});

/// Share of the roasting gas a whole bean has released after `day` days.
class DegassingCurve {
  const DegassingCurve({required this.scaleDays, required this.shape});

  /// Weibull scale λ: days to release about 63 % of the gas.
  final double scaleDays;

  /// Weibull shape k; below 1 the release slows down over time.
  final double shape;

  double releasedBy(double day) =>
      day <= 0 ? 0 : 1 - math.exp(-math.pow(day / scaleDays, shape));

  /// Day by which [share] (between 0 and 1) of the gas has been released.
  double dayReleasing(double share) =>
      scaleDays * math.pow(-math.log(1 - share), 1 / shape);

  DegassingCurve scaledBy(double factor) =>
      DegassingCurve(scaleDays: scaleDays * factor, shape: shape);
}

/// Weibull fits of Smrke et al. (2018, table 2) for medium-speed roasts:
/// dark 78, medium 101 and light 131 Colorette Pt. An omni roast, between
/// medium and light (about 116 Pt), takes the midpoint of those two fits.
/// The light roast measured over 800 h, where the release keeps slowing,
/// stands in for ultra-light.
const degassingCurves = {
  'dark': DegassingCurve(scaleDays: 190 / 24, shape: 0.93),
  'medium': DegassingCurve(scaleDays: 232 / 24, shape: 0.99),
  'omni': DegassingCurve(scaleDays: 304.5 / 24, shape: 0.995),
  'light': DegassingCurve(scaleDays: 377 / 24, shape: 1.0),
  'ultra_light': DegassingCurve(scaleDays: 715 / 24, shape: 0.842),
};

/// Released-gas share at which each phase ends, per style. Filter is ready
/// once 40 % of the gas is out, espresso at 55 %; aromas are at their best
/// until 80–85 % and staling sets in as the last of the gas leaves.
const _thresholds = {
  BrewStyle.filter: (prime: 0.40, primeEnd: 0.80, good: 0.90, aging: 0.97),
  BrewStyle.espresso: (prime: 0.55, primeEnd: 0.85, good: 0.90, aging: 0.97),
};

/// Days after roasting at which each phase ends. `primeStart` is also the
/// end of the degassing phase.
class FreshnessWindow {
  const FreshnessWindow({
    required this.primeStart,
    required this.primeEnd,
    required this.goodUntil,
    required this.agingUntil,
  });

  final int primeStart;
  final int primeEnd;
  final int goodUntil;
  final int agingUntil;

  FreshnessPhase phaseAt(int day) {
    if (day < primeStart) return FreshnessPhase.degassing;
    if (day <= primeEnd) return FreshnessPhase.prime;
    if (day <= goodUntil) return FreshnessPhase.good;
    if (day <= agingUntil) return FreshnessPhase.aging;
    return FreshnessPhase.stale;
  }

  /// Days left in the current phase, counting today; null once stale.
  int? daysLeftInPhase(int day) => switch (phaseAt(day)) {
    FreshnessPhase.degassing => primeStart - day,
    FreshnessPhase.prime => primeEnd - day + 1,
    FreshnessPhase.good => goodUntil - day + 1,
    FreshnessPhase.aging => agingUntil - day + 1,
    FreshnessPhase.stale => null,
  };

  @override
  bool operator ==(Object other) =>
      other is FreshnessWindow &&
      other.primeStart == primeStart &&
      other.primeEnd == primeEnd &&
      other.goodUntil == goodUntil &&
      other.agingUntil == agingUntil;

  @override
  int get hashCode => Object.hash(primeStart, primeEnd, goodUntil, agingUntil);

  @override
  String toString() =>
      'FreshnessWindow($primeStart–$primeEnd, $goodUntil, $agingUntil)';
}

/// Degassing curve for a roast level (medium when unknown). A roaster's
/// recommended rest speeds up or slows down the curve so that filter is
/// ready on that day. Beyond a factor of 3 (or below 0.5) the curve would
/// describe an implausible bean, so the rest of the gap becomes `offsetDays`
/// that shift every date instead.
({DegassingCurve curve, double offsetDays}) degassingCurve({
  required String? roastLevel,
  int? restDays,
}) {
  final curve = degassingCurves[roastLevel] ?? degassingCurves['medium']!;
  if (restDays == null || restDays <= 0) return (curve: curve, offsetDays: 0);
  final filterPrime = _thresholds[BrewStyle.filter]!.prime;
  final factor = (restDays / curve.dayReleasing(filterPrime)).clamp(0.5, 3.0);
  final scaled = curve.scaledBy(factor);
  return (
    curve: scaled,
    offsetDays: restDays - scaled.dayReleasing(filterPrime),
  );
}

/// The fits cover about a month of measurements, so later dates are
/// extrapolated. Windows end by this many days after roasting, or 45 days
/// after the coffee is ready if that is later; the phases after readiness
/// shrink in proportion to fit.
const _maxShelfDays = 90;
const _minDaysAfterReady = 45;

FreshnessWindow freshnessWindow({
  required String? roastLevel,
  required BrewStyle style,
  int? restDays,
}) {
  final (:curve, :offsetDays) = degassingCurve(
    roastLevel: roastLevel,
    restDays: restDays,
  );
  final limits = _thresholds[style]!;
  final start = curve.dayReleasing(limits.prime) + offsetDays;
  final ends = [
    for (final share in [limits.primeEnd, limits.good, limits.aging])
      curve.dayReleasing(share) + offsetDays,
  ];
  final cap = math.max(_maxShelfDays, start + _minDaysAfterReady);
  final shrink = ends.last > cap ? (cap - start) / (ends.last - start) : 1.0;
  final days = [for (final end in ends) start + (end - start) * shrink];
  final primeStart = start.round();
  final primeEnd = math.max(primeStart, days[0].round());
  final goodUntil = math.max(primeEnd + 1, days[1].round());
  return FreshnessWindow(
    primeStart: primeStart,
    primeEnd: primeEnd,
    goodUntil: goodUntil,
    agingUntil: math.max(goodUntil + 1, days[2].round()),
  );
}

/// Whole local days between [roastDate] and [now], or null when the roast
/// date lies in the future (e.g. a device clock that is behind).
int? daysSinceRoast(DateTime roastDate, DateTime now) {
  final roastDay = DateTime.utc(roastDate.year, roastDate.month, roastDate.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(roastDay).inDays;
  return days < 0 ? null : days;
}

/// Once a bag is opened, air replaces its protective atmosphere and aroma is
/// lost faster: over 8 weeks methanethiol fell to about 15 % in opened bags
/// against 33 % in sealed ones (Smrke et al., Food Packaging and Shelf Life
/// 2022, doi:10.1016/j.fpsl.2022.100893), about 1.7 times the rate.
const openedBagAgingFactor = 1.7;

/// Effective days since [roastDate] on [today]: days spent frozen do not
/// count, and days since [openedDate] count [openedBagAgingFactor] times.
/// Null when roasted in the future (e.g. a wrong device clock).
int? effectiveRoastAge(
  DateTime roastDate,
  DateTime today, {
  int frozenPauseDays = 0,
  DateTime? openedDate,
}) {
  int daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  final days = daysBetween(roastDate, today);
  if (days < 0) return null;
  var age = (days - frozenPauseDays).toDouble();
  if (openedDate != null) {
    final open = daysBetween(openedDate, today).clamp(0, days);
    age += open * (openedBagAgingFactor - 1);
  }
  return age < 0 ? 0 : age.round();
}

/// One rated brew as input for [findSweetSpot].
class RatedBrewSample {
  const RatedBrewSample({
    required this.day,
    required this.rating,
    required this.weight,
  });

  /// Days after roasting when the brew was made.
  final int day;

  /// Rating on the app's 0–10 scale.
  final double rating;

  /// How much the brew tells about the coffee being viewed, from 0 to 1.
  final double weight;
}

class SweetSpot {
  const SweetSpot({
    required this.startDay,
    required this.endDay,
    required this.averageRating,
    required this.brewCount,
  });

  final int startDay;
  final int endDay;

  /// Smoothed rating at the best day.
  final double averageRating;

  /// Brews made within the sweet spot.
  final int brewCount;
}

/// How much a rated brew of another coffee says about this one. The same
/// coffee counts fully; a coffee of the same roast level counts less, more
/// so from the same roaster, whose roasting style and packaging are alike.
/// Other roast levels degas at another pace and do not count.
double sweetSpotWeight({
  required bool sameCoffee,
  required bool sameRoastLevel,
  required bool sameRoaster,
}) {
  if (sameCoffee) return 1;
  if (!sameRoastLevel) return 0;
  return sameRoaster ? 0.5 : 0.25;
}

/// Days after roasting when ratings are highest, from a Gaussian-weighted
/// average of ratings by day (a kernel smoother with [bandwidthDays]).
///
/// Returns null without enough evidence: fewer than [minimumBrews] weighted
/// brews, brews spanning under a week, or a best day that doesn't beat the
/// weakest well-supported day by at least [minimumGain] points. The spot
/// covers the days around the best one that stay within half a point of it.
SweetSpot? findSweetSpot(
  List<RatedBrewSample> samples, {
  double bandwidthDays = 3,
  int minimumBrews = 5,
  double minimumGain = 1,
}) {
  final usable = samples.where((sample) => sample.weight > 0).toList();
  if (usable.length < minimumBrews) return null;
  final firstDay = usable.map((sample) => sample.day).reduce(math.min);
  final lastDay = usable.map((sample) => sample.day).reduce(math.max);
  if (lastDay - firstDay < 7) return null;

  final smoothed = <int, double>{};
  final support = <int, double>{};
  for (var day = firstDay; day <= lastDay; day++) {
    var weights = 0.0;
    var total = 0.0;
    for (final sample in usable) {
      final distance = (sample.day - day) / bandwidthDays;
      final weight = sample.weight * math.exp(-0.5 * distance * distance);
      weights += weight;
      total += weight * sample.rating;
    }
    // Only days with the equivalent of two nearby brews are trusted.
    if (weights < 2 * math.exp(-0.5)) continue;
    smoothed[day] = total / weights;
    support[day] = weights;
  }
  if (smoothed.length < 2) return null;
  final best = smoothed.entries.reduce((a, b) => b.value > a.value ? b : a);
  final weakest = smoothed.values.reduce(math.min);
  if (best.value - weakest < minimumGain) return null;

  var start = best.key;
  var end = best.key;
  while ((smoothed[start - 1] ?? -1) >= best.value - 0.5) {
    start--;
  }
  while ((smoothed[end + 1] ?? -1) >= best.value - 0.5) {
    end++;
  }
  return SweetSpot(
    startDay: start,
    endDay: end,
    averageRating: best.value,
    brewCount: usable
        .where((sample) => sample.day >= start && sample.day <= end)
        .length,
  );
}
