import 'dart:async';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/domain/marklife_protocol.dart';

class MarklifeSession {
  MarklifeSession({
    required this.write,
    this.encodeJob = MarklifeProtocol.job,
    this.requiresCredits = true,
    this.responseFailure,
    this.acknowledgement,
    this.trace,
    this.creditTimeout = const Duration(seconds: 5),
    this.resultTimeout = const Duration(seconds: 15),
    this.packetDelay = const Duration(milliseconds: 30),
  });

  final Future<void> Function(Uint8List) write;
  final BleTrace? trace;
  final Uint8List Function(Uint8List, int, MarklifePaper) encodeJob;
  final bool requiresCredits;
  final MarklifeFailure? Function(Uint8List)? responseFailure;
  final bool Function(Uint8List)? acknowledgement;
  final Duration creditTimeout;
  final Duration resultTimeout;
  final Duration packetDelay;
  int _credits = 0;
  int _transportPayload = 20;
  int _devicePayload = 90;
  bool _closed = false;
  bool _printing = false;
  bool _awaitingResult = false;
  bool _accepted = false;
  MarklifeFailure? _failure;
  MarklifeFailure? _deviceFailure;

  int get payloadBytes => _transportPayload.clamp(1, _devicePayload);

  void setMtu(int mtu) {
    _transportPayload = (mtu - 3).clamp(20, 90);
    _event('mtu', {'mtu': mtu, 'payload': payloadBytes});
  }

  void receiveControl(Uint8List bytes) {
    if (_closed) return;
    if (bytes.length == 2 && bytes[0] == 1) {
      _credits = (_credits + bytes[1]).clamp(0, 255);
      _event('credits', {'available': _credits});
    } else if (bytes.length == 3 && bytes[0] == 2) {
      final mtu = bytes[1] | bytes[2] << 8;
      if (mtu >= 23) _devicePayload = (mtu - 3).clamp(20, 90);
      _event('deviceMtu', {'mtu': mtu, 'payload': payloadBytes});
    } else {
      _event('controlUnknown', {'length': bytes.length});
    }
  }

  void receive(Uint8List bytes) {
    if (_closed) return;
    if (responseFailure case final decode?) {
      final failure = decode(bytes);
      if (failure != null) {
        _deviceFailure = failure;
        if (_printing) _failure = failure;
        _event('printerStatus', {'failure': failure.name});
        return;
      }
    } else if (bytes.length == 2 && bytes[0] == 0xff) {
      final code = bytes[1];
      _deviceFailure = switch (code) {
        1 => MarklifeFailure.paper,
        2 => MarklifeFailure.cover,
        3 => MarklifeFailure.hot,
        4 => MarklifeFailure.battery,
        5 => null,
        _ => _deviceFailure,
      };
      if (_printing && _deviceFailure != null) _failure = _deviceFailure;
      _event('printerStatus', {'code': code});
      return;
    }
    final accepted =
        acknowledgement?.call(bytes) ??
        ((bytes.length == 1 && const [0xaa, 0x4f, 0x4b].contains(bytes[0])) ||
            (bytes.length == 2 && bytes[0] == 0x4f && bytes[1] == 0x4b));
    if (accepted && _awaitingResult) _accepted = true;
    _event('response', {
      'length': bytes.length,
      'accepted': accepted && _awaitingResult,
    });
  }

  void close() {
    _closed = true;
    _credits = 0;
  }

  void _event(String event, Map<String, Object?> data) =>
      emitBleTrace(trace, 'marklife.$event', data);

  void _check() {
    if (_closed) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
    if (_failure case final failure?) throw MarklifeException(failure);
  }

  Future<void> _until(
    bool Function() ready,
    Duration timeout,
    MarklifeFailure failure,
  ) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      _check();
      if (clock.elapsed >= timeout) throw MarklifeException(failure);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _check();
  }

  Future<void> print(
    Uint8List pixels,
    int lengthMm,
    MarklifePaper paper,
  ) async {
    if (_printing) throw const MarklifeException(MarklifeFailure.busy);
    _check();
    if (_deviceFailure case final failure?) throw MarklifeException(failure);
    final bytes = encodeJob(pixels, lengthMm, paper);
    _printing = true;
    _accepted = false;
    _awaitingResult = false;
    final deadline = Stopwatch()..start();
    _event('job', {
      'lengthMm': lengthMm,
      'paper': paper.name,
      'bytes': bytes.length,
    });
    try {
      for (var offset = 0; offset < bytes.length;) {
        _check();
        if (deadline.elapsed > const Duration(seconds: 60)) {
          throw const MarklifeException(MarklifeFailure.unconfirmed);
        }
        if (requiresCredits) {
          await _until(
            () => _credits > 0,
            creditTimeout,
            MarklifeFailure.credits,
          );
        }
        final end = (offset + payloadBytes).clamp(0, bytes.length);
        // Subscribe before writes, including the last write's synchronous ACK.
        // Ignore unsolicited success bytes received before the final packet.
        _awaitingResult = end == bytes.length;
        if (requiresCredits) _credits--;
        await write(Uint8List.sublistView(bytes, offset, end));
        _check();
        offset = end;
        if (offset < bytes.length) await Future<void>.delayed(packetDelay);
      }
      _event('sent', {'bytes': bytes.length});
      await _until(() => _accepted, resultTimeout, MarklifeFailure.unconfirmed);
      _event('accepted', {});
    } on Object {
      // An uncertain job cannot be retried on this session.
      close();
      rethrow;
    } finally {
      _printing = false;
      _awaitingResult = false;
    }
  }
}
