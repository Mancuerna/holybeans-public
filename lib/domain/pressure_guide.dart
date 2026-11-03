import 'package:holybeans/domain/shot_curve.dart';

/// An immutable reference on the original extraction clock, without stretching
/// its duration or extending a pressure target beyond the measured interval.
class PressureGuide {
  PressureGuide._(this.timesMs, this.bars);

  static PressureGuide? fromCurve(ShotCurve curve) {
    final times = curve.timesMs;
    final bars = curve.pressure;
    if (times.length < 2 || bars.length != times.length) return null;
    for (var i = 0; i < times.length; i++) {
      if (times[i] < 0 ||
          (i > 0 && times[i] <= times[i - 1]) ||
          !bars[i].isFinite ||
          bars[i] < 0 ||
          bars[i] > 30) {
        return null;
      }
    }
    if (!bars.any((bar) => bar > 0)) return null;
    return PressureGuide._(List.unmodifiable(times), List.unmodifiable(bars));
  }

  final List<int> timesMs;
  final List<double> bars;
  int get endMs => timesMs.last;

  double? targetAt(int milliseconds) {
    if (milliseconds < timesMs.first || milliseconds > endMs) return null;
    var low = 0;
    var high = timesMs.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (timesMs[middle] < milliseconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return bars.first;
    final fraction =
        (milliseconds - timesMs[low - 1]) / (timesMs[low] - timesMs[low - 1]);
    return bars[low - 1] + (bars[low] - bars[low - 1]) * fraction;
  }
}
