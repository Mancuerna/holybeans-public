import 'package:holybeans/domain/shot_curve.dart';

/// One reading from a Bluetooth scale.
class ScaleReading {
  const ScaleReading({
    required this.grams,
    this.flowGramsPerSecond = 0,
    this.timerMs = 0,
    this.timerRunning,
    this.timerAutoStopped = false,
    this.batteryPercent,
  });

  /// Weight on the scale, negative after taring with something lifted off.
  final double grams;

  /// Flow the scale works out from the weight, in g/s.
  final double flowGramsPerSecond;

  /// The scale's own timer, in milliseconds.
  final int timerMs;

  /// Explicit timer state when the device reports only whole seconds.
  /// Null uses the usual inference from changes in [timerMs].
  final bool? timerRunning;

  /// Whether the scale stopped automatically rather than by a timer-button press.
  final bool timerAutoStopped;
  final int? batteryPercent;
}

/// What the app may ask a scale to do: tare and drive its timer. Scales
/// are otherwise only read.
enum ScaleCommand {
  tare,
  startTimer,
  stopTimer,
  resetTimer,

  /// Tares, resets the timer and starts it, in one go.
  tareAndStartTimer,
}

/// The weight of a brew over time, built from a scale's readings as they
/// arrive. Readings come several times a second; keeping one every
/// [minGapMs] is plenty to draw and keeps the saved curve small.
class WeightRecording {
  WeightRecording({this.minGapMs = 100, this.tareWaitMs = 1500});

  final int minGapMs;

  /// How long to wait for a tare to show before recording anyway.
  final int tareWaitMs;
  final _times = <int>[];
  final _weight = <double>[];
  final _flow = <double>[];
  bool _awaitingTare = false;
  ShotCurve? _curve;

  bool get isEmpty => _times.isEmpty;

  /// Last weight recorded, if any.
  double? get lastGrams => _weight.isEmpty ? null : _weight.last;

  /// Highest weight recorded: the water poured, even if the dripper is
  /// lifted off at the end.
  double? get peakGrams => _weight.isEmpty
      ? null
      : _weight.reduce((top, grams) => grams > top ? grams : top);

  /// Clears the recording and waits for the scale to read about zero: just
  /// after a tare it still sends the old weight for a moment.
  void restartAfterTare() {
    clear();
    _awaitingTare = true;
  }

  /// Adds [reading], taken [elapsedMs] after the brew started. Readings
  /// too close to the previous one, or out of order, are skipped.
  void add(int elapsedMs, ScaleReading reading) {
    if (_awaitingTare) {
      if (reading.grams.abs() > 1 && elapsedMs < tareWaitMs) return;
      _awaitingTare = false;
    }
    if (_times.isNotEmpty && elapsedMs - _times.last < minGapMs) return;
    _times.add(elapsedMs);
    _weight.add(reading.grams);
    _flow.add(reading.flowGramsPerSecond);
    _curve = null;
  }

  void clear() {
    _awaitingTare = false;
    _curve = null;
    _times.clear();
    _weight.clear();
    _flow.clear();
  }

  /// The recorded curve (weight and flow, no pressure), or null with fewer
  /// than two readings. The same object until another reading is added,
  /// so a chart only redraws when there is something new.
  ShotCurve? get curve => _times.length < 2
      ? null
      : _curve ??= ShotCurve(
          timesMs: [..._times],
          flow: [..._flow],
          weight: [..._weight],
        );
}
