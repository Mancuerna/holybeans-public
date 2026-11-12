import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/domain/statistics.dart';

/// A pour found on a scale curve: when the weight left its resting level,
/// when it reached the next one, and how much water that added.
class DetectedPour {
  const DetectedPour({
    required this.startMs,
    required this.endMs,
    required this.grams,
  });

  final int startMs;
  final int endMs;
  final double grams;
}

/// Weight within this many grams counts as still.
const _stillGrams = 1.0;

/// How long the weight must stay still to be a rest between pours.
const _stillMs = 3000;

/// Half the window the weight is smoothed over, so that a swirl or a
/// knock on the scale does not count as a change.
const _smoothMs = 250;

/// Bloom rests are at least this long.
const _bloomRestMs = 15000;

/// A bloom takes up to this many times the dose of water (or this share of
/// the water without a dose). Real blooms run from about two to almost five
/// times the dose, so this alone cannot tell a big dose's first pour apart.
const _bloomDoseMultiple = 5.0;
const _bloomWaterShare = 0.3;

/// A later bloom is not much bigger than the first one: a pour of twice the
/// water after two similar blooms, even followed by a long wait, is a pour.
const _bloomGrowth = 1.5;

/// The pours on a scale [curve] of a filter brew.
///
/// The curve is read as resting levels joined by pours: a pour is the
/// step from one level, where the weight stays still for a few seconds, to
/// the next. Whatever happens in between, such as swirling or lifting the
/// dripper, only counts by the weight it leaves: a swirl that settles back
/// adds nothing. Steps under 3 g (or 1.5 % of the water) are noise.
List<DetectedPour> detectPours(ShotCurve curve) {
  final times = curve.timesMs;
  if (times.length < 2 || curve.weight.length != times.length) return const [];
  final weight = _smoothed(times, curve.weight);
  final levels = _restingLevels(times, weight);
  if (levels.isEmpty) return const [];
  // A curve that starts while pouring rests at zero before it.
  if (levels.first.from > 0 && weight.first < levels.first.grams - 2) {
    levels.insert(0, (from: 0, to: 0, grams: 0));
  }
  final minimum = [
    3.0,
    levels.last.grams * 0.015,
  ].reduce((a, b) => a > b ? a : b);
  final pours = <DetectedPour>[];
  var previous = levels.first;
  for (final level in levels.skip(1)) {
    final step = level.grams - previous.grams;
    if (step >= minimum) {
      var start = previous.to;
      while (start < level.from &&
          weight[start] <= previous.grams + _stillGrams) {
        start++;
      }
      var end = level.from;
      while (end > start && weight[end] >= level.grams - _stillGrams) {
        end--;
      }
      pours.add(
        DetectedPour(startMs: times[start], endMs: times[end], grams: step),
      );
      previous = level;
    } else if (step <= -minimum) {
      // Weight taken off the scale: count on from what is left.
      previous = level;
    }
  }
  return pours;
}

/// [detectPours] as blooms and pours for a brew of [doseGrams], as
/// [brewPoursOf] tells them apart. Null when the curve shows no pours or
/// more than a brew can record.
BrewPours? brewPoursFromCurve(
  ShotCurve curve, {
  double? doseGrams,
  int? bloomCount,
  int? pourCount,
}) => brewPoursOf(
  detectPours(curve),
  doseGrams: doseGrams,
  bloomCount: bloomCount,
  pourCount: pourCount,
);

/// Completes missing phase rows in [recorded] from a filter brew's [curve].
///
/// Keeps existing counts and details. Returns `null` when detection disagrees
/// with the counts or all phases already have details.
BrewPours? completeBrewPoursFromCurve(
  ShotCurve curve, {
  required BrewPours recorded,
  double? doseGrams,
}) {
  if (recorded.hasAllPhases) return null;
  final detected = brewPoursFromCurve(
    curve,
    doseGrams: doseGrams,
    bloomCount: recorded.bloomCount,
    pourCount: recorded.pourCount,
  );
  return detected == null ? null : recorded.fillMissingPhases(detected);
}

/// [pours], in order, as blooms and pours for a brew of [doseGrams]. The
/// first [bloomCount] pours are blooms when given. With only [pourCount],
/// the remaining leading pours are blooms. Incompatible counts return null.
/// Without either count, the first small pours followed by a long rest are
/// blooms: up to five times the dose
/// each and no later one much bigger than the first, so a first pour of a
/// large dose followed by a wait is not taken for a bloom. Null without
/// pours or with more than a brew can record.
BrewPours? brewPoursOf(
  List<DetectedPour> pours, {
  double? doseGrams,
  int? bloomCount,
  int? pourCount,
}) {
  if (pours.isEmpty ||
      (bloomCount != null &&
          (bloomCount < 0 || bloomCount > BrewPours.maxBlooms)) ||
      (pourCount != null &&
          (pourCount < 0 || pourCount > BrewPours.maxPours))) {
    return null;
  }
  final total = pours.fold(0.0, (sum, pour) => sum + pour.grams);
  int restAfter(int index) => index + 1 < pours.length
      ? pours[index + 1].startMs - pours[index].endMs
      : 0;
  var blooms = 0;
  if (bloomCount != null) {
    blooms = bloomCount;
  } else if (pourCount != null) {
    blooms = pours.length - pourCount;
  } else {
    final largest = doseGrams != null && doseGrams > 0
        ? doseGrams * _bloomDoseMultiple
        : total * _bloomWaterShare;
    while (blooms < BrewPours.maxBlooms &&
        blooms < pours.length - 1 &&
        pours[blooms].grams <= largest &&
        (blooms == 0 || pours[blooms].grams <= pours[0].grams * _bloomGrowth) &&
        restAfter(blooms) >= _bloomRestMs) {
      blooms++;
    }
  }
  if (blooms < 0 || blooms > BrewPours.maxBlooms || blooms > pours.length) {
    return null;
  }
  final rest = pours.length - blooms;
  if (rest > BrewPours.maxPours || (pourCount != null && rest != pourCount)) {
    return null;
  }
  int? seconds(int ms) => ms >= 500 ? (ms / 1000).round() : null;
  return BrewPours(
    bloomCount: blooms,
    pourCount: rest,
    phases: [
      for (final (index, pour) in pours.indexed)
        BrewPourPhase(
          kind: index < blooms ? BrewPourKind.bloom : BrewPourKind.pour,
          number: index < blooms ? index + 1 : index - blooms + 1,
          waterGrams: (pour.grams * 10).round() / 10,
          durationSeconds: seconds(pour.endMs - pour.startMs),
          restSeconds: index < blooms ? seconds(restAfter(index)) : null,
        ),
    ],
  );
}

/// [weight] with each sample replaced by the median of those within
/// [_smoothMs] of it.
List<double> _smoothed(List<int> times, List<double> weight) {
  final smoothed = <double>[];
  var from = 0;
  var to = 0;
  for (var i = 0; i < times.length; i++) {
    while (times[from] < times[i] - _smoothMs) {
      from++;
    }
    while (to + 1 < times.length && times[to + 1] <= times[i] + _smoothMs) {
      to++;
    }
    smoothed.add(upperMedian(weight.getRange(from, to + 1)));
  }
  return smoothed;
}

typedef _Level = ({int from, int to, double grams});

/// The stretches where the weight stays within [_stillGrams] of itself for
/// at least [_stillMs], with their median weight.
List<_Level> _restingLevels(List<int> times, List<double> weight) {
  final levels = <_Level>[];
  var i = 0;
  while (i < times.length) {
    var j = i;
    var low = weight[i];
    var high = weight[i];
    while (j + 1 < times.length) {
      final next = weight[j + 1];
      final nextLow = next < low ? next : low;
      final nextHigh = next > high ? next : high;
      if (nextHigh - nextLow > 2 * _stillGrams) break;
      low = nextLow;
      high = nextHigh;
      j++;
    }
    if (times[j] - times[i] >= _stillMs) {
      levels.add((
        from: i,
        to: j,
        grams: upperMedian(weight.getRange(i, j + 1)),
      ));
      i = j + 1;
    } else {
      i++;
    }
  }
  return levels;
}
