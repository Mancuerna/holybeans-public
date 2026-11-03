import 'dart:math' as math;

/// Round tick values for an axis from 0 to at least [max]: steps of 1, 2 or
/// 5 times a power of ten, with three to six intervals, choosing the one
/// whose top is closest to [max] (fewer ticks on a tie). Empty when [max] is
/// not positive.
List<double> axisTicks(double max) {
  if (!max.isFinite || max <= 0) return const [];
  final exponent = (math.log(max) / math.ln10).floor();
  double? bestStep;
  var bestTop = double.infinity;
  for (var power = exponent - 2; power <= exponent; power++) {
    for (final factor in const [1, 2, 5]) {
      final step = factor * math.pow(10, power).toDouble();
      final intervals = (max / step - 1e-9).ceil();
      if (intervals < 3 || intervals > 6) continue;
      final top = intervals * step;
      if (top < bestTop - 1e-9) {
        bestTop = top;
        bestStep = step;
      }
    }
  }
  final step = bestStep ?? max / 4;
  final count = (max / step - 1e-9).ceil();
  // Rounded so that 0.1 steps do not print as 0.30000000000000004.
  return [for (var i = 0; i <= count; i++) (i * step * 1e6).round() / 1e6];
}

/// Round tick values inside [min]..[max], for axes that need not start at
/// zero (time aligned by first drip runs negative). The step is the one
/// [axisTicks] would pick for the span; the first tick is the first multiple
/// of it at or after [min]. Empty when the range is empty.
List<double> rangeTicks(double min, double max) {
  if (!min.isFinite || !max.isFinite || max <= min) return const [];
  final span = axisTicks(max - min);
  if (span.length < 2) return const [];
  final step = span[1] - span[0];
  final first = (min / step - 1e-9).ceil();
  return [
    for (var i = first; i * step <= max + 1e-9; i++)
      ((i * step) * 1e6).round() / 1e6,
  ];
}

/// Tick times in seconds from 0 to at most [max], on steps a clock reads
/// well (5, 10, 15 or 30 s, or whole minutes): the shortest step that leaves
/// at most five intervals. Empty when [max] is not positive.
List<double> timeTicks(double max) {
  if (!max.isFinite || max <= 0) return const [];
  const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600];
  final step = steps.firstWhere(
    (step) => max / step <= 5 + 1e-9,
    orElse: () => (max / 5 / 3600).ceil() * 3600,
  );
  return [for (var t = 0; t <= max + 1e-9; t += step) t.toDouble()];
}

/// The range an axis should cover for [values], leaving out a few isolated
/// readings far beyond the rest, such as a knock on the scale or a cup set
/// down at the end of a brew: on each side, values past twice the 1st or
/// 99th percentile (or past zero when that percentile is on the other side)
/// are left out when they are at most 1 % of the readings. More of them
/// are taken as real and kept. The chart clips what is left out, and the
/// recorded values do not change.
({double low, double high}) robustRange(List<double> values) {
  if (values.isEmpty) return (low: 0, high: 0);
  final sorted = [...values]..sort();
  final n = sorted.length;
  // Too few readings to tell a spike from the brew itself.
  if (n < 20) return (low: sorted.first, high: sorted.last);
  final allowed = math.max(1, n ~/ 100);
  final p99 = sorted[((n - 1) * 0.99).floor()];
  final p1 = sorted[((n - 1) * 0.01).ceil()];
  final highLimit = p99 > 0 ? 2 * p99 : 0.0;
  final lowLimit = p1 < 0 ? 2 * p1 : 0.0;
  final above = sorted.where((value) => value > highLimit).length;
  final below = sorted.where((value) => value < lowLimit).length;
  return (
    low: below == 0 || below > allowed ? sorted.first : sorted[below],
    high: above == 0 || above > allowed ? sorted.last : sorted[n - 1 - above],
  );
}
