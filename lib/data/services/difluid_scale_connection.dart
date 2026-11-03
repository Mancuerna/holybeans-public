import 'dart:async';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/domain/difluid_scale_protocol.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:universal_ble/universal_ble.dart';

/// Readings and documented timer button actions on one DiFluid connection.
/// Polling reads sensor data without enabling auto-send or changing units.
class DifluidScaleConnection {
  DifluidScaleConnection({
    required this.id,
    required this.service,
    required this.characteristic,
    this.trace,
  });

  final BleTrace? trace;

  final String id;
  final String service;
  final String characteristic;
  Timer? _dataPoller;
  Timer? _statusPoller;
  bool _active = true;
  bool _dataPolling = false;
  bool _statusPolling = false;
  int _pollCount = 0;
  int? _battery;
  int? _unit;
  bool? _timing;
  bool _autoStopped = false;
  Completer<int>? _statusAnswer;

  /// Consumes status replies too, without presenting them as weight samples.
  ScaleReading? parse(Uint8List packet) {
    if (!_active) return null;
    if (parseDifluidScaleStatus(packet) case final status?) {
      emitBleTrace(trace, 'difluid.status', {
        'state': status.state,
        'battery': status.battery,
      });
      _battery = status.battery;
      if (status.state == 14) {
        _autoStopped = true;
      } else if (status.state == 10 || status.state == 11) {
        _autoStopped = false;
      }
      // Keep automatic-stop provenance if the result later returns to idle.
      if (status.state == 10) {
        _timing = true;
      } else if (_idle(status.state) || _paused(status.state)) {
        _timing = false;
      }
      final answer = _statusAnswer;
      if (answer != null && !answer.isCompleted) answer.complete(status.state);
      return null;
    }
    if (parseDifluidScaleUnit(packet) case final unit?) _unit = unit;
    return parseDifluidScaleReading(
      packet,
      batteryPercent: _battery,
      legacyUnit: _unit,
      timerRunning: _timing,
      timerAutoStopped: _autoStopped,
    );
  }

  Future<void> _write(List<int> bytes) async {
    if (!_active) throw StateError('Scale disconnected');
    emitBleTrace(trace, 'write.start', {
      'service': service,
      'characteristic': characteristic,
      'bytes': bleHex(bytes),
    });
    try {
      await UniversalBle.write(
        id,
        service,
        characteristic,
        Uint8List.fromList(bytes),
      );
      emitBleTrace(trace, 'write.ok', {'bytes': bleHex(bytes)});
    } on Object catch (error, stack) {
      emitBleTrace(trace, 'write.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      rethrow;
    }
  }

  /// Verifies the cleartext channel before reporting a successful pairing.
  Future<void> start() async {
    await _write(difluidGetScaleUnit);
    await _readStatus();
    await _write(difluidGetScaleData);
    if (!_active) return;
    _dataPoller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_pollData());
    });
    _statusPoller = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_pollStatus());
    });
  }

  Future<void> _pollData() async {
    if (!_active || _dataPolling) return;
    _dataPolling = true;
    try {
      await _write(difluidGetScaleData);
      if (++_pollCount % 20 == 0) {
        await _write(difluidGetScaleUnit);
      }
    } on Object {
      // Connection loss is reported by BleLink; a missed read is retried.
    } finally {
      _dataPolling = false;
    }
  }

  Future<void> _pollStatus() async {
    if (!_active || _statusPolling || _statusAnswer != null) return;
    _statusPolling = true;
    try {
      await _write(difluidGetScaleStatus);
    } on Object {
      // Data polling remains independent of status and battery failures.
    } finally {
      _statusPolling = false;
    }
  }

  Future<int> _readStatus() async {
    final answer = Completer<int>();
    _statusAnswer = answer;
    try {
      await _write(difluidGetScaleStatus);
      final state = await answer.future.timeout(
        const Duration(milliseconds: 800),
      );
      emitBleTrace(trace, 'difluid.handshake', {'state': state});
      return state;
    } on Object catch (error, stack) {
      emitBleTrace(trace, 'difluid.status.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      rethrow;
    } finally {
      if (identical(_statusAnswer, answer)) _statusAnswer = null;
    }
  }

  Future<int> _waitFor(bool Function(int) accepts) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final state = await _readStatus();
      if (accepts(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Scale timer did not acknowledge the action');
  }

  static bool _idle(int state) => const {2, 5, 13}.contains(state);
  static bool _paused(int state) => state == 11 || state == 14;

  Future<int> _readyStatus() async {
    final state = await _readStatus();
    return state == 4 || state == 7
        ? _waitFor((state) => _idle(state) || _paused(state) || state == 10)
        : state;
  }

  /// Pause with DLink Press; a click exits the stopped result screen.
  Future<void> _reset() async {
    var state = await _readyStatus();
    if (state == 10) {
      await _write(difluidScaleTimerPause);
      state = await _waitFor((state) => _paused(state) || _idle(state));
    }
    if (_paused(state)) {
      await _write(difluidScaleTimerClick);
      await _waitFor(_idle);
    } else if (!_idle(state)) {
      throw StateError('Scale is not ready to reset its timer');
    }
  }

  Future<void> _startTimer() async {
    var state = await _readyStatus();
    if (_paused(state)) {
      // Check whether the click started timing or exited the Stop screen
      // before sending any second click.
      await _write(difluidScaleTimerClick);
      state = await _waitFor((state) => state == 10 || _idle(state));
    }
    if (state == 10) return;
    if (!_idle(state)) {
      throw StateError('Scale is not ready to start its timer');
    }
    await _write(difluidScaleTimerClick);
    await _waitFor((state) => state == 10);
  }

  Future<void> _stopTimer() async {
    final state = await _readyStatus();
    if (_paused(state) || _idle(state)) return;
    if (state != 10) throw StateError('Scale is not timing');
    await _write(difluidScaleTimerPause);
    await _waitFor((state) => _paused(state) || _idle(state));
  }

  Future<void> _tare() async {
    final state = await _readyStatus();
    if (_paused(state)) {
      await _write(difluidScaleTimerClick);
      await _waitFor(_idle);
    } else if (!_idle(state) && state != 10) {
      throw StateError('Scale is not ready to tare');
    }
    await _write(difluidScaleTare);
    await _waitFor((state) => _idle(state) || state == 10);
  }

  /// The caller serializes commands so a reset cannot race with Start.
  Future<bool> send(ScaleCommand command) async {
    if (!_active) return false;
    emitBleTrace(trace, 'command', {'command': command.name});
    try {
      switch (command) {
        case ScaleCommand.tare:
          await _tare();
        case ScaleCommand.startTimer:
          await _startTimer();
        case ScaleCommand.stopTimer:
          await _stopTimer();
        case ScaleCommand.resetTimer:
          await _reset();
        case ScaleCommand.tareAndStartTimer:
          await _reset();
          await _tare();
          await _startTimer();
      }
      return _active;
    } on Object catch (error, stack) {
      emitBleTrace(trace, 'command.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      return false;
    }
  }

  /// Stops all reads immediately, including after unexpected radio loss.
  void close() {
    _active = false;
    _dataPoller?.cancel();
    _dataPoller = null;
    _statusPoller?.cancel();
    _statusPoller = null;
    final answer = _statusAnswer;
    if (answer != null && !answer.isCompleted) answer.complete(-1);
    _statusAnswer = null;
  }
}
