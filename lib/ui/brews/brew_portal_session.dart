import 'dart:async';

import 'package:holybeans/data/services/portal_sensor.dart';
import 'package:holybeans/domain/portal_protocol.dart';

class BrewPortalSession {
  BrewPortalSession(this.sensor) {
    _subscription = sensor.readings.listen(_onReading);
    sensor.addListener(_connectionChanged);
    unawaited(sensor.connect(automatic: true));
  }
  final BlePortalSensor sensor;
  final _clock = Stopwatch();
  final _samples = <PortalSample>[];
  late final StreamSubscription<PortalReading> _subscription;
  int _origin = 0;
  bool _newSegment = true;

  PortalRecording? get recording =>
      _samples.isEmpty ? null : PortalRecording(List.of(_samples));

  void _connectionChanged() {
    if (!sensor.connected) _newSegment = true;
  }

  void _onReading(PortalReading reading) {
    if (!_clock.isRunning) return;
    final ms = _origin + _clock.elapsedMilliseconds;
    _samples.add((
      ms: ms,
      reading: reading,
      start:
          _newSegment || (_samples.isNotEmpty && ms - _samples.last.ms > 5000),
    ));
    _newSegment = false;
  }

  void start(int seconds) {
    final requested = seconds * 1000;
    _origin = _samples.isNotEmpty && _samples.last.ms > requested
        ? _samples.last.ms
        : requested;
    _newSegment = true;
    _clock
      ..reset()
      ..start();
  }

  void stop() => _clock.stop();
  void reset() {
    stop();
    _samples.clear();
  }

  void dispose() {
    sensor.removeListener(_connectionChanged);
    unawaited(_subscription.cancel());
  }
}
