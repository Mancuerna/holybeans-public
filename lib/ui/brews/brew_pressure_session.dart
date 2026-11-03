import 'dart:async';

import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/domain/pressure_recording.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// The pressure sensor during one brew form: it records the pressure while
/// the brew timer runs. Unlike a scale it receives no commands; it only
/// follows the timer.
class BrewPressureSession {
  BrewPressureSession(this.sensor, {Stopwatch? stopwatch})
    : _watch = stopwatch ?? Stopwatch() {
    _readings = sensor.readings.listen(_onReading);
    sensor.addListener(_connectionChanged);
    // Reconnect to the paired sensor as soon as the form opens.
    unawaited(sensor.connect(automatic: true));
  }

  final PressureSensor sensor;
  final _recording = PressureRecording();
  final Stopwatch _watch;
  final trace = PressureTrace();
  int _traceOffsetMs = 0;
  late final StreamSubscription<double> _readings;

  bool get recording => _watch.isRunning;

  /// Highest pressure while the timer ran, if the sensor sent any.
  double? get peakBar => _recording.peakBar;

  void _onReading(double bar) {
    if (_watch.isRunning) {
      _recording.add(_watch.elapsedMilliseconds, bar);
      if (sensor.connected) {
        trace.add(_traceOffsetMs + _watch.elapsedMilliseconds, bar);
      }
    }
  }

  void _connectionChanged() {
    if (!sensor.connected) trace.breakSegment();
  }

  void timerStarted(int fromSeconds) {
    if (fromSeconds == 0 && _watch.elapsedMilliseconds == 0) {
      _recording.clear();
      trace.clear();
    }
    // Resume on the form's displayed clock, without altering saved recording.
    _traceOffsetMs = fromSeconds * 1000 - _watch.elapsedMilliseconds;
    trace.breakSegment();
    _watch.start();
  }

  void timerStopped() {
    _watch.stop();
    trace.breakSegment();
  }

  void timerReset() {
    _watch
      ..stop()
      ..reset();
    _recording.clear();
    trace.clear();
    _traceOffsetMs = 0;
  }

  /// [curve] (the scale's) with the recorded pressure added.
  ShotCurve withPressure(ShotCurve curve) => _recording.addTo(curve);

  void dispose() {
    sensor.removeListener(_connectionChanged);
    unawaited(_readings.cancel());
  }
}
