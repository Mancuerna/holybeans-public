import 'dart:async';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/domain/acaia_protocol.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:universal_ble/universal_ble.dart';

class AcaiaScaleConnection {
  AcaiaScaleConnection({
    required this.id,
    required this.service,
    required this.notify,
    required this.write,
    required this.classic,
    required this.withResponse,
    required this.supportsWriteWithoutResponse,
    this.trace,
  });

  final String id;
  final String service;
  final String notify;
  final String write;
  final bool classic;
  final bool withResponse;
  final bool supportsWriteWithoutResponse;
  final BleTrace? trace;
  final _decoder = AcaiaDecoder();
  final _clock = Stopwatch()..start();
  final _ready = Completer<bool>();
  final _settingsReady = Completer<bool>();
  int _writeSequence = 0;
  Timer? _recovery;
  bool _active = true;
  bool _busy = false;
  int _lastPacketMs = 0;
  int _lastHeartbeatMs = 0;
  Future<void> _queue = Future.value();

  List<ScaleReading> parse(Uint8List bytes) {
    if (!_active) return const [];
    final now = _clock.elapsedMilliseconds;
    final readings = _decoder.add(bytes, elapsedMs: now);
    if (_decoder.hasSettings && !_settingsReady.isCompleted) {
      _settingsReady.complete(true);
    }
    if (readings.isNotEmpty && !_ready.isCompleted) _ready.complete(true);
    _lastPacketMs = now;
    unawaited(_onNotification(now));
    return readings;
  }

  Future<void> _write(List<int> bytes, {bool withoutResponse = false}) {
    final useResponse = withResponse && !withoutResponse;
    final operation = _queue.then((_) async {
      if (!_active) throw StateError('Acaia disconnected');
      final sequence = ++_writeSequence;
      final started = _clock.elapsedMicroseconds;
      final context = {
        'sequence': sequence,
        'bytes': bleHex(bytes),
        'length': bytes.length,
        'withResponse': useResponse,
        'service': service,
        'characteristic': write,
      };
      emitBleTrace(trace, 'acaia.write', context);
      try {
        await UniversalBle.write(
          id,
          service,
          write,
          Uint8List.fromList(bytes),
          withoutResponse: !useResponse,
        );
        emitBleTrace(trace, 'acaia.write.ok', {
          ...context,
          'durationUs': _clock.elapsedMicroseconds - started,
        });
      } on Object catch (error, stack) {
        emitBleTrace(trace, 'acaia.write.error', {
          ...context,
          'durationUs': _clock.elapsedMicroseconds - started,
          'error': '$error',
          'stack': '$stack',
        });
        rethrow;
      }
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _negotiateMtu() async {
    final started = _clock.elapsedMicroseconds;
    emitBleTrace(trace, 'acaia.mtu.start', {'expectedMtu': 247});
    try {
      final mtu = await UniversalBle.requestMtu(id, 247);
      emitBleTrace(trace, 'acaia.mtu.ok', {
        'expectedMtu': 247,
        'mtu': mtu,
        'durationUs': _clock.elapsedMicroseconds - started,
      });
    } on Object catch (error, stack) {
      emitBleTrace(trace, 'acaia.mtu.error', {
        'expectedMtu': 247,
        'durationUs': _clock.elapsedMicroseconds - started,
        'error': '$error',
        'stack': '$stack',
      });
    }
  }

  Future<void> start() async {
    // Identification and subscription are not gated on a settings reply.
    // Readiness still requires known units and an actual decoded reading.
    await _negotiateMtu();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!classic) {
      try {
        await _write(acaiaAndroidWakeUp);
      } on Object {
        // The traced wake-up is best effort; readings still decide readiness.
      }
    }
    await _write(
      acaiaIdentify(classic: classic),
      withoutResponse: supportsWriteWithoutResponse,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _write(acaiaSubscribe, withoutResponse: supportsWriteWithoutResponse);
    if (!_active) throw StateError('Acaia disconnected');
    _lastPacketMs = _clock.elapsedMilliseconds;
    _lastHeartbeatMs = _lastPacketMs;
    _recovery = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_busy && _active) unawaited(_recoverIfSilent());
    });
    if (!await _settingsReady.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Acaia: no valid unit settings'),
    )) {
      throw StateError('Acaia disconnected before sending settings');
    }
    if (!await _ready.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw TimeoutException('Acaia: no decoded weight reading'),
    )) {
      throw StateError('Acaia disconnected before sending readings');
    }
  }

  Future<void> _recoverIfSilent() async {
    if (_clock.elapsedMilliseconds - _lastPacketMs < 1000) return;
    _busy = true;
    try {
      await _write(
        acaiaIdentify(classic: classic),
        withoutResponse: supportsWriteWithoutResponse,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _write(
        acaiaSubscribe,
        withoutResponse: supportsWriteWithoutResponse,
      );
    } on Object {
      // BleLink observes disconnection; recovery remains best effort.
    } finally {
      _busy = false;
    }
  }

  Future<void> _onNotification(int now) async {
    if (_lastHeartbeatMs == 0 || _busy || now - _lastHeartbeatMs < 1000) {
      return;
    }
    _busy = true;
    _lastHeartbeatMs = now;
    try {
      if (!classic) {
        await _write(acaiaIdentify(classic: classic));
      }
      await _write(acaiaHeartbeat);
    } on Object {
      // A failed heartbeat must not become an unhandled asynchronous error.
    } finally {
      _busy = false;
    }
  }

  Future<bool> send(ScaleCommand command) async {
    if (!_active || !_decoder.ready) return false;
    try {
      for (final frame in acaiaCommands(command)) {
        await _write(frame, withoutResponse: supportsWriteWithoutResponse);
      }
      if (!_active) return false;
      _decoder.commanded(command);
      return true;
    } on Object {
      return false;
    }
  }

  void close() {
    _active = false;
    _recovery?.cancel();
    if (!_ready.isCompleted) _ready.complete(false);
    if (!_settingsReady.isCompleted) _settingsReady.complete(false);
  }
}
