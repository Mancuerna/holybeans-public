/// Rules that let a Bluetooth scale drive the brew timer: its own timer
/// button, the first drop after "Wait for the first drip" and the end of an
/// espresso. They only read the scale's readings; any command still goes
/// through the brew timer.
library;

/// Follows the scale's own timer, which every reading carries, to tell when
/// its button starts or stops it. A reading with a later time means it
/// runs; two more readings with the same time mean it stopped; a lower time
/// means it was reset.
class ScaleTimerWatch {
  int? _lastMs;
  int _unchanged = 0;
  bool? _running;

  bool? get running => _running;
  bool wasReset = false;

  void clear() {
    _lastMs = null;
    _unchanged = 0;
    _running = null;
    wasReset = false;
  }

  /// True when the scale's timer has just started, false when it has just
  /// stopped, null otherwise (including the first state seen, so a timer
  /// already running when the form opens does not count as a press).
  bool? add(int timerMs, {bool? isRunning}) {
    final last = _lastMs;
    wasReset = last != null && last > 0 && timerMs == 0;
    _lastMs = timerMs;
    if (isRunning != null) {
      final before = _running;
      _running = isRunning;
      _unchanged = 0;
      return before == null || before == isRunning ? null : isRunning;
    }
    if (last == null) return null;
    final bool running;
    if (timerMs > last) {
      _unchanged = 0;
      running = true;
    } else if (timerMs == last) {
      _unchanged++;
      if (_unchanged < 2) return null;
      running = false;
    } else {
      _unchanged = 0;
      running = false;
    }
    final before = _running;
    _running = running;
    if (before == null || before == running) return null;
    return running;
  }
}

/// Weight within this many grams of zero counts as an empty, tared cup:
/// a Bookoo at rest wanders by up to 0.3 g with the machine vibrating.
const _zeroGrams = 0.3;

/// The median of [values].
double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

/// Finds the first drop once the cup is on the tared scale: first a
/// reading at zero (the tare has applied), then the weight, as the median
/// of the last [window] readings, at [thresholdGrams] or more. A knock or a
/// vibration moves one or two readings, never the median, so it does not
/// count; real drops reach a gram within half a second. Moving the cup
/// belongs before the tare, which is why waiting starts with one.
class FirstDripWatch {
  FirstDripWatch({this.thresholdGrams = 1, this.window = 5});

  final double thresholdGrams;
  final int window;
  final _recent = <double>[];
  int? _atZeroMs;

  /// The time of the reading at [ms] when the drops had begun: the last
  /// one where the cup was still at zero. Null until then.
  int? add(int ms, double grams) {
    if (grams.abs() <= _zeroGrams) _atZeroMs = ms;
    final since = _atZeroMs;
    if (since == null) return null;
    _recent.add(grams);
    if (_recent.length > window) _recent.removeAt(0);
    if (_recent.length < window ~/ 2 + 1) return null;
    return _median(_recent) >= thresholdGrams ? since : null;
  }
}

/// Tells when an espresso stops dripping: after [minElapsedMs], once the
/// cup holds at least the dose (a 1:1 ratio, or [fallbackGrams] without
/// one), when the weight rose less than [minRiseGrams] in the last
/// [quietMs]. The weight is the median of three readings, so a knock does
/// not count. The scale's own flow is not used: it trails the weight by
/// over a second and rarely reads zero.
class ShotEndWatch {
  ShotEndWatch({
    this.minRiseGrams = 0.2,
    this.minElapsedMs = 5000,
    this.quietMs = 1000,
    this.fallbackGrams = 5,
  });

  final double minRiseGrams;
  final int minElapsedMs;
  final int quietMs;
  final double fallbackGrams;
  final _raw = <double>[];
  final _smoothed = <(int, double)>[];

  /// When the shot ended, that is when the weight stopped rising, once it
  /// is clear; null until then.
  int? add({required int elapsedMs, required double grams, double? doseGrams}) {
    _raw.add(grams);
    if (_raw.length > 3) _raw.removeAt(0);
    final weight = _median(_raw);
    _smoothed.add((elapsedMs, weight));
    // Keep one reading from before the quiet stretch to compare with.
    while (_smoothed.length > 1 && _smoothed[1].$1 <= elapsedMs - quietMs) {
      _smoothed.removeAt(0);
    }
    final enough = doseGrams != null && doseGrams > 0
        ? doseGrams
        : fallbackGrams;
    if (elapsedMs <= minElapsedMs || weight < enough) return null;
    final (sinceMs, before) = _smoothed.first;
    if (elapsedMs - sinceMs < quietMs) return null;
    return weight - before < minRiseGrams ? sinceMs : null;
  }

  void reset() {
    _raw.clear();
    _smoothed.clear();
  }
}
