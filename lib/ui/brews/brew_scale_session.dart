import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/espresso_scale_guard.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/scale_automation.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Who started or stopped the brew timer, which decides what the scale is
/// told: it is never asked to repeat what it did itself.
enum _Source { app, scaleButton, firstDrip, shotEnd }

/// The scale during one brew form. It follows the brew timer (tare and
/// start, stop, reset) and records the weight while the timer runs, so the
/// curve is saved with the brew. The other way round, the scale's timer
/// button starts and stops the brew timer, "Wait for the first drip" starts
/// it with the first drop and, in an espresso, the end of the drops stops
/// it. A finished pour from the assistant brings its own curve, which
/// replaces the timer's.
class BrewScaleSession extends ChangeNotifier {
  BrewScaleSession(
    this.scale, {
    DateTime Function()? clock,
    Stopwatch? stopwatch,
    @visibleForTesting ShotEndWatch Function()? shotEnd,
  }) : _clock = clock ?? DateTime.now,
       _watch = stopwatch ?? Stopwatch(),
       _newShotEnd = shotEnd ?? ShotEndWatch.new {
    _readings = scale.readings.listen(_onReading);
    scale.addListener(_onScaleChanged);
    _wasConnected = scale.connected;
    _resetDialOnce();
    // Reconnect to the paired scale as soon as the form opens.
    unawaited(scale.connect(automatic: true));
  }

  bool _dialReset = false;
  bool _wasConnected = false;
  bool _disposed = false;
  bool startFailed = false;
  bool weighingDose = false;
  bool _ignoreWeighingTimer = false;

  void beginDoseWeighing() {
    weighingDose = true;
    _ignoreWeighingTimer = true;
    _dripWatch = null;
    _scaleTimer.clear();
    _pendingTimerChange = false;
    _pendingReset = false;
    notifyListeners();
  }

  void endDoseWeighing() {
    weighingDose = false;
    notifyListeners();
  }

  bool resetting = false;
  Future<bool> _resetCommand = Future.value(false);
  bool get restartsOnNextStart => _restartOnStart;
  bool _restartOnStart = false;
  bool _pendingTimerChange = false;
  bool _pendingReset = false;
  int _commandsInFlight = 0;
  int _runId = 0;

  void _onScaleChanged() {
    final connected = scale.connected;
    if (connected != _wasConnected) {
      _wasConnected = connected;
      if (!connected) {
        flowTrace.breakSegment();
        _scaleTimer.clear();
        _pendingTimerChange = false;
        _pendingReset = false;
        _dripWatch = null;
        if (recording) _requestStop(_Source.scaleButton);
      }
      notifyListeners();
    }
    _resetDialOnce();
  }

  /// A brew starts from a clean dial: time left on the scale's timer from
  /// before keeps it from taring and starting with the timer.
  void _resetDialOnce() {
    if (_dialReset || !scale.connected || recording) return;
    _dialReset = true;
    unawaited(_send(ScaleCommand.resetTimer));
  }

  final Scale scale;
  final DateTime Function() _clock;
  final ShotEndWatch Function() _newShotEnd;
  final _recording = WeightRecording();
  final _espressoGuard = EspressoScaleGuard();
  bool _awaitingTare = false;
  final Stopwatch _watch;
  final flowTrace = FlowTrace();
  DateTime? _flowReadingAt;
  int _flowOffsetMs = 0;

  bool get hasRecentFlowReading =>
      _flowReadingAt != null &&
      _clock().difference(_flowReadingAt!) < FlowTrace.staleAfter;

  double? get flowGramsPerSecond =>
      recording && scale.connected && hasRecentFlowReading
      ? flowTrace.current
      : null;

  double? get guideWeightGrams {
    final weight = recording
        ? (scale.connected && hasRecentFlowReading
              ? _recording.lastGrams
              : null)
        : beverageGrams;
    return weight != null && weight.isFinite && weight >= -0.3
        ? (weight < 0 ? 0 : weight)
        : null;
  }

  final _scaleTimer = ScaleTimerWatch();
  late final StreamSubscription<ScaleReading> _readings;
  ShotCurve? _poured;

  /// How the form asks the brew timer to start or stop (with the brew time
  /// in seconds when the end came before it was told), whether the brew is
  /// an espresso, its dose and where the first drip goes; set by the form.
  VoidCallback? requestStart;
  ValueChanged<int?>? requestStop;
  bool Function() isEspresso = () => false;
  double? Function() doseGrams = () => null;
  ValueChanged<int>? onFirstDrip;

  _Source _source = _Source.app;
  FirstDripWatch? _dripWatch;
  ShotEndWatch? _shotEnd;

  /// Looks for the espresso's first drip while the timer runs; null once
  /// noted, or when the timer started with it.
  FirstDripWatch? _espressoDrip;

  /// The scale read zero since the timer started: the cup is tared and the
  /// readings are what fell into it, not a stale or absolute weight.
  bool _tared = false;

  /// The scale's timer reacts to our own commands for a moment; its
  /// changes are ignored meanwhile.
  DateTime _commandsSettleAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether the weight is being recorded now.
  bool get recording => _watch.isRunning;

  /// Waiting for the first drop to start the timer.
  bool get waitingForDrip => _dripWatch != null;

  /// The curve to save with the brew, if one was recorded.
  ShotCurve? get curve => _poured ?? _recording.curve;

  /// Recorded water, excluding the reading before the initial tare.
  double? get pouredGrams =>
      recordedWaterGrams(_poured) ?? _recording.peakGrams;

  /// Highest accepted beverage weight, preserved after the cup is lifted.
  double? get beverageGrams =>
      recordedWaterGrams(_poured) ?? _recording.peakGrams;

  /// Sends [command], then [then] once it is written.
  Future<bool> _send(
    ScaleCommand command, [
    ScaleCommand? then,
    bool stopOnFailure = false,
  ]) {
    final run = _runId;
    _commandsInFlight++;
    _commandsSettleAt = _clock().add(const Duration(seconds: 2));
    return () async {
      var success = false;
      try {
        success = await scale.send(command);
        if (success && then != null && !_disposed && run == _runId) {
          success = await scale.send(then);
        }
      } on Object {
        success = false;
      } finally {
        _commandsInFlight--;
        if (!_disposed) {
          _commandsSettleAt = _clock().add(const Duration(seconds: 2));
          if (!success && stopOnFailure && run == _runId && recording) {
            startFailed = true;
            _requestStop(_Source.scaleButton);
            notifyListeners();
          }
        }
      }
      return success;
    }();
  }

  /// Tares and waits for the first drop to start the timer.
  void waitForDrip() {
    if (recording || resetting) return;
    unawaited(_send(ScaleCommand.tare));
    _dripWatch = FirstDripWatch();
    notifyListeners();
  }

  void cancelWaitForDrip() {
    _dripWatch = null;
    notifyListeners();
  }

  void _requestStart(_Source source) {
    _source = source;
    requestStart?.call();
  }

  void _requestStop(_Source source, [int? atSeconds]) {
    _source = source;
    requestStop?.call(atSeconds);
    if (!recording) _source = _Source.app;
  }

  static int _seconds(int ms) => (ms / 1000).round().clamp(1, 1 << 30);

  void _onReading(ScaleReading reading) {
    if (resetting || weighingDose) {
      _scaleTimer.clear();
      return;
    }
    if (_ignoreWeighingTimer) {
      _scaleTimer.clear();
      if (reading.timerRunning == false ||
          (reading.timerRunning != true && reading.timerMs == 0)) {
        _ignoreWeighingTimer = false;
      }
      return;
    }
    if (waitingForDrip) {
      // Waiting is owned by the app: automatic timer activity is not a press.
      _scaleTimer.clear();
      _pendingReset = false;
      _pendingTimerChange = false;
      if (_dripWatch!.add(_clock().millisecondsSinceEpoch, reading.grams) !=
          null) {
        _dripWatch = null;
        _requestStart(_Source.firstDrip);
      }
      return;
    }
    // A zero in the notification that starts the timer already confirms tare.
    // During a running brew, keep recording the final sample before stopping.
    final wasRecording = recording;
    if (!wasRecording) _followScaleTimer(reading);
    if (_awaitingTare && reading.grams.abs() <= 1) {
      _awaitingTare = false;
    }
    // A button on the weighing platform can hold a large load for several
    // seconds. Wait for zero before seeding either the recording or its guard.
    final measured = recording && _awaitingTare
        ? null
        : recording && isEspresso()
        ? _espressoGuard.add(_watch.elapsedMilliseconds, reading)
        : reading;
    if (_watch.isRunning) {
      if (measured == null) {
        flowTrace.breakSegment();
      } else if (_recording.add(_watch.elapsedMilliseconds, measured)) {
        flowTrace.add(
          _flowOffsetMs + _watch.elapsedMilliseconds,
          measured.grams,
        );
        _flowReadingAt = _clock();
      }
    }
    if (wasRecording) _followScaleTimer(reading);
    if (!recording || !isEspresso() || measured == null) return;
    final elapsedMs = _watch.elapsedMilliseconds;
    if (_espressoDrip?.add(elapsedMs, measured.grams) case final dripMs?) {
      _espressoDrip = null;
      onFirstDrip?.call(_seconds(dripMs));
    }
    if (measured.grams.abs() <= 0.3) _tared = true;
    if (!_tared) return;
    if (_shotEnd?.add(
          elapsedMs: elapsedMs,
          grams: measured.grams,
          doseGrams: doseGrams(),
        )
        case final endMs?) {
      // Noted when the weight stopped rising, not a second later when that
      // was clear.
      _requestStop(_Source.shotEnd, _seconds(endMs));
    }
  }

  void _followScaleTimer(ScaleReading reading) {
    if (recording && isEspresso() && reading.timerAutoStopped) {
      // Keep tracking the clock without interpreting an automatic pause/reset
      // as a button press. Espresso still ends from its actual weight curve.
      _scaleTimer.add(reading.timerMs, isRunning: true);
      _pendingReset = false;
      _pendingTimerChange = false;
      return;
    }
    final pressed = _scaleTimer.add(
      reading.timerMs,
      isRunning: reading.timerRunning,
    );
    if (_scaleTimer.wasReset && (recording || _watch.elapsedMilliseconds > 0)) {
      _pendingReset = true;
    }
    if (_scaleTimer.running == true) _pendingReset = false;
    if (_commandsInFlight > 0 || !_clock().isAfter(_commandsSettleAt)) {
      if (pressed != null || _pendingReset) _pendingTimerChange = true;
    } else {
      final state = _pendingTimerChange ? _scaleTimer.running : pressed;
      _pendingTimerChange = false;
      if (_pendingReset) {
        _pendingReset = false;
        final keepResult =
            isEspresso() &&
            curve != null &&
            (!recording ||
                (_watch.elapsedMilliseconds >= 5000 &&
                    (beverageGrams ?? 0) >= (doseGrams() ?? 5)));
        if (keepResult) {
          // Auto mode can send zero while its display retains the final result.
          // Stop and fill the result before marking the next start as fresh.
          _requestStop(_Source.scaleButton);
          _restartOnStart = true;
        } else {
          _restartOnStart = true;
          _requestStop(_Source.scaleButton, 0);
        }
      } else if (state == true && !recording) {
        _requestStart(_Source.scaleButton);
      } else if (state == false && recording) {
        _requestStop(_Source.scaleButton);
      }
    }
  }

  /// Starts or resumes recording at [fromSeconds].
  ///
  /// A fresh start from either button clears the recording and waits for zero.
  /// The app tares and restarts the scale; the scale's own button needs no
  /// repeated command. Starting on the first drop keeps the already tared
  /// weight, and resuming preserves the recording.
  void timerStarted(int fromSeconds) {
    _ignoreWeighingTimer = false;
    final source = _source;
    _source = _Source.app;
    // Without the scale the app clock runs alone, with no curve.
    if (!scale.connected) return;
    _runId++;
    startFailed = false;
    if (_restartOnStart) {
      _watch.reset();
      _restartOnStart = false;
    }
    _dripWatch = null;
    final fresh = fromSeconds == 0 && _watch.elapsedMilliseconds == 0;
    if (fresh) {
      flowTrace.clear();
      _espressoGuard.clear();
      _awaitingTare = source == _Source.app || source == _Source.scaleButton;
      _recording.clear();
      _poured = null;
      // A shot started by its first drop has no first drip to note.
      _espressoDrip = source == _Source.firstDrip ? null : FirstDripWatch();
      _tared = source == _Source.firstDrip;
      _shotEnd = _newShotEnd();
    }
    switch (source) {
      case _Source.app when fresh:
        // A dial with time on it does not tare and start in one go.
        _pendingTimerChange = true;
        unawaited(
          _send(ScaleCommand.resetTimer, ScaleCommand.tareAndStartTimer, true),
        );
      case _Source.app || _Source.firstDrip:
        _pendingTimerChange = true;
        unawaited(_send(ScaleCommand.startTimer, null, true));
      case _Source.scaleButton || _Source.shotEnd:
        break;
    }
    _flowOffsetMs = fromSeconds * 1000 - _watch.elapsedMilliseconds;
    _flowReadingAt = null;
    flowTrace.breakSegment();
    _watch.start();
    notifyListeners();
  }

  void timerStopped() {
    _runId++;
    final source = _source;
    _source = _Source.app;
    _watch.stop();
    flowTrace.breakSegment();
    _shotEnd?.reset();
    if (source != _Source.scaleButton) {
      unawaited(_send(ScaleCommand.stopTimer));
    }
    notifyListeners();
  }

  void timerReset() {
    _runId++;
    _restartOnStart = false;
    _pendingReset = false;
    _pendingTimerChange = false;
    _scaleTimer.clear();
    _watch
      ..stop()
      ..reset();
    _recording.clear();
    flowTrace.clear();
    _flowReadingAt = null;
    _flowOffsetMs = 0;
    _espressoGuard.clear();
    _awaitingTare = false;
    _poured = null;
    _dripWatch = null;
    _espressoDrip = null;
    startFailed = false;
    _source = _Source.app;
    _resetCommand = _send(ScaleCommand.resetTimer);
    notifyListeners();
  }

  Future<bool> resetWeightAndTimer(VoidCallback resetAppTimer) async {
    if (_disposed || resetting || !scale.connected) return false;
    resetting = true;
    notifyListeners();
    try {
      // Use the normal reset path to clear the app timer, curve and sensors
      // without committing the discarded extraction as a finished brew.
      resetAppTimer();
      final run = _runId;
      final device = scale.activeScaleId;
      if (!await _resetCommand ||
          _disposed ||
          run != _runId ||
          !scale.connected ||
          scale.activeScaleId != device) {
        return false;
      }
      return await _send(ScaleCommand.tare);
    } finally {
      resetting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Keeps the curve recorded by the pour assistant.
  void pourFinished(ShotCurve? curve) {
    if (curve != null) _poured = curve;
  }

  @override
  void dispose() {
    _disposed = true;
    _runId++;
    scale.removeListener(_onScaleChanged);
    _readings.cancel();
    super.dispose();
  }
}
