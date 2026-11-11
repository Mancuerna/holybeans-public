import 'dart:async';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_identity.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';

enum LabelPrintFailure { disconnected, unsupported, rejected, timeout, busy }

class LabelPrintException implements Exception {
  const LabelPrintException(this.failure, {this.code});
  final LabelPrintFailure failure;
  final int? code;
  @override
  String toString() => 'LabelPrintException(${failure.name}, $code)';
}

class NiimbotSession {
  NiimbotSession({
    required this.write,
    this.model = LabelPrinterModel.d110,
    this.responseTimeout = const Duration(seconds: 5),
    this.printTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 300),
    this.trace,
    this.rowBatchBytes,
  });

  final Future<void> Function(Uint8List bytes) write;
  final LabelPrinterModel model;
  final Duration responseTimeout;
  final Duration printTimeout;
  final Duration pollInterval;
  final BleTrace? trace;
  final int Function()? rowBatchBytes;
  final _decoder = NiimbotDecoder();
  Completer<NiimbotPacket>? _response;
  int? _expected;
  LabelPrintException? _failure;
  NiimbotIdentity? _identity;
  NiimbotIdentity? get identity => _identity;
  bool _identified = false;
  bool _printing = false;
  bool _acceptLegacyPageIndex = false;
  int _legacyPages = 0;
  bool _trackD11HRows = false;
  int? _lastD11HRow;

  void receive(Uint8List bytes) {
    final packets = _decoder.add(bytes);
    if (!_identified) {
      emitBleTrace(trace, 'niimbot.receive', {
        'bytes': bytes.length,
        'decoded': packets.length,
        'buffered': _decoder.bufferedBytes,
        'invalidFrames': _decoder.invalidFrames,
        'expected': _expected,
      });
    }
    for (final packet in packets) {
      if (_trackD11HRows && packet.command == 0xd3) {
        if (packet.payload.length < 2) {
          _fail(const LabelPrintException(LabelPrintFailure.rejected));
        } else {
          final row = packet.payload[0] * 256 + packet.payload[1];
          if (_lastD11HRow == null || row > _lastD11HRow!) _lastD11HRow = row;
        }
      }
      if (_acceptLegacyPageIndex && packet.command == 0xe0) {
        if (packet.payload.length != 2) {
          _fail(const LabelPrintException(LabelPrintFailure.rejected));
        } else {
          _legacyPages = packet.payload[0] * 256 + packet.payload[1];
        }
      }
      if (!_identified && _expected != null && packet.command != _expected) {
        emitBleTrace(trace, 'niimbot.unexpectedResponse', {
          'command': packet.command,
          'expected': _expected,
          'length': packet.payload.length,
        });
      }
      if (!_identified &&
          const [0xc2, 0x48, 0xb5, 0xdb, 0x00].contains(packet.command)) {
        emitBleTrace(trace, 'niimbot.response', {
          'command': packet.command,
          'payload': packet.payload.take(32).toList(),
        });
      }
      if (packet.command == 0xdb || packet.command == 0x00) {
        _fail(
          LabelPrintException(
            LabelPrintFailure.rejected,
            code: packet.payload.firstOrNull,
          ),
        );
      } else if (packet.command == _expected) {
        final response = _response;
        if (response != null && !response.isCompleted) {
          response.complete(packet);
        }
      }
    }
  }

  void _fail(LabelPrintException error) {
    _failure = error;
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(error);
    }
  }

  void close() {
    _identified = false;
    _identity = null;
    _fail(const LabelPrintException(LabelPrintFailure.disconnected));
  }

  void _check() {
    if (_failure case final failure?) throw failure;
  }

  Future<NiimbotPacket> _request(
    int command,
    int reply, [
    List<int> payload = const [1],
  ]) async {
    _check();
    if (_response != null) {
      throw const LabelPrintException(LabelPrintFailure.busy);
    }
    final response = Completer<NiimbotPacket>();
    _response = response;
    _expected = reply;
    if (!_identified && const [0xc1, 0x40, 0xa5].contains(command)) {
      emitBleTrace(trace, 'niimbot.request', {
        'command': command,
        'reply': reply,
        'payload': payload,
      });
    }
    // A response can arrive before the platform write future completes.
    // Both must succeed; neither a late write failure nor an early reply may
    // escape observation or overlap the next command.
    NiimbotPacket? received;
    try {
      await Future.wait<void>([
        response.future.timeout(responseTimeout).then((packet) {
          received = packet;
        }),
        Future<void>.sync(() async {
          await write(NiimbotPacket(command, payload).encode());
          if (!_identified && const [0xc1, 0x40, 0xa5].contains(command)) {
            emitBleTrace(trace, 'niimbot.writeComplete', {'command': command});
          }
        }),
      ], eagerError: true);
      return received!;
    } on TimeoutException {
      const error = LabelPrintException(LabelPrintFailure.timeout);
      _failure = error; // A late ACK must never acknowledge the next job.
      throw error;
    } finally {
      _response = null;
      _expected = null;
    }
  }

  Future<void> identify() async {
    _identified = false;
    _identity = null;
    final hello = await _request(0xc1, 0xc2);
    if (!const [1, 2, 3].contains(hello.payload.firstOrNull)) {
      throw const LabelPrintException(LabelPrintFailure.unsupported);
    }
    // B1 Pro and D11-H negotiate status immediately after C1, before the model query,
    // as in NiimBlueLib connectNegotiate / niimbot-web detectPrinter.
    // Keep the already tested legacy models' handshake unchanged.
    final protocolFirst =
        model == LabelPrinterModel.b1Pro || model == LabelPrinterModel.d11H;
    int? version;
    if (model == LabelPrinterModel.d11) {
      // NiimBlueLib: C2[1] is legacy; C2[2] selects protocol 1 (D110).
      // Do not guess a page format for newer or malformed D11 greetings.
      if (hello.payload.length != 1 || hello.payload.single == 3) {
        throw const LabelPrintException(LabelPrintFailure.unsupported);
      }
      version = hello.payload.single == 1 ? 0 : 1;
    }
    if (model == LabelPrinterModel.d110M) {
      // Follow connectNegotiate: only greeting 3 requests status. Older
      // D110_M greetings select the B1 task without a status query.
      if (hello.payload.length != 1) {
        throw const LabelPrintException(LabelPrintFailure.unsupported);
      }
      version = hello.payload.single - 1;
      if (hello.payload.single == 3) {
        version = niimbotProtocolVersion((await _request(0xa5, 0xb5)).payload);
        if (version == 0) {
          throw const LabelPrintException(LabelPrintFailure.unsupported);
        }
      }
    }
    if (protocolFirst) {
      version = niimbotProtocolVersion((await _request(0xa5, 0xb5)).payload);
    }
    final identity = await _request(0x40, 0x48, [8]);
    final modelId = switch (identity.payload) {
      [final high] => high << 8,
      [final high, final low] => high * 256 + low,
      _ => -1,
    };
    if (!model.acceptsId(modelId)) {
      throw const LabelPrintException(LabelPrintFailure.unsupported);
    }
    if (model.needsProtocolVersion && !protocolFirst) {
      version = niimbotProtocolVersion((await _request(0xa5, 0xb5)).payload);
    }
    try {
      _identity = NiimbotIdentity.resolve(
        model,
        modelId,
        protocolVersion: version,
      );
    } on FormatException {
      throw const LabelPrintException(LabelPrintFailure.unsupported);
    }
    _identified = true;
  }

  Future<void> _ack(
    int command,
    int reply, [
    List<int> payload = const [1],
  ]) async {
    final response = await _request(command, reply, payload);
    if (response.payload.isEmpty || response.payload.first == 0) {
      throw const LabelPrintException(LabelPrintFailure.rejected);
    }
  }

  Future<void> _sendRows(List<NiimbotPacket> rows) async {
    final batchLimit = model == LabelPrinterModel.d11H
        ? (rowBatchBytes?.call() ?? 0).clamp(0, 240)
        : 0;
    if (batchLimit >= 31) {
      final batch = <int>[];
      for (final row in rows) {
        _check();
        final frame = row.encode();
        if (batch.isNotEmpty && batch.length + frame.length > batchLimit) {
          await write(Uint8List.fromList(batch));
          batch.clear();
          _check();
        }
        batch.addAll(frame);
      }
      if (batch.isNotEmpty) {
        _check();
        await write(Uint8List.fromList(batch));
      }
      return;
    }
    for (final row in rows) {
      _check();
      if (row.command == 0x86) {
        // Checkpoint replies are row data, not boolean ACKs.
        final reply = await _request(0x86, 0xd3, row.payload);
        if (reply.payload.isEmpty) {
          throw const LabelPrintException(LabelPrintFailure.rejected);
        }
      } else {
        await write(row.encode());
      }
    }
  }

  Future<void> _waitForCopies(int copies) async {
    final deadline = DateTime.now().add(printTimeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw const LabelPrintException(LabelPrintFailure.timeout);
      }
      await Future<void>.delayed(pollInterval);
      final status = (await _request(0xa3, 0xb3)).payload;
      if (status.length < 4 || (status.length == 10 && status[6] != 0)) {
        throw LabelPrintException(
          LabelPrintFailure.rejected,
          code: status.length == 10 ? status[6] : null,
        );
      }
      if (status[0] * 256 + status[1] >= copies) return;
    }
  }

  Future<void> _waitForLegacyCopies(int copies) async {
    final deadline = DateTime.now().add(printTimeout);
    while (true) {
      _check();
      if (_legacyPages == copies) return;
      if (DateTime.now().isAfter(deadline)) {
        throw const LabelPrintException(LabelPrintFailure.timeout);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  // Only the documented B21 readiness/completion commands may return busy (0).
  // A timeout or transport failure stops the job; bitmap data is never retried.
  Future<void> _pollReady(int command, int reply) async {
    final deadline = DateTime.now().add(printTimeout);
    while (true) {
      final response = (await _request(command, reply)).payload;
      if (response.length != 1 || (response[0] != 0 && response[0] != 1)) {
        throw const LabelPrintException(LabelPrintFailure.rejected);
      }
      if (response[0] == 1) return;
      if (DateTime.now().isAfter(deadline)) {
        throw const LabelPrintException(LabelPrintFailure.timeout);
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> print(Uint8List pixels, int width, {int copies = 1}) async {
    if (_printing) throw const LabelPrintException(LabelPrintFailure.busy);
    final identity = _identity;
    if (!_identified || identity == null) {
      throw const LabelPrintException(LabelPrintFailure.disconnected);
    }
    if (copies < 1 || copies > 10) throw ArgumentError.value(copies);
    final family = identity.family;
    final legacy =
        family == NiimbotPrintFamily.b21 || family == NiimbotPrintFamily.b21L2b;
    final rows = niimbotImageRows(
      pixels,
      width,
      model: model,
      totalCounts: legacy,
      checkLines: legacy,
    );
    final height = pixels.length ~/ width;
    final size = [
      ...niimbotU16(model.rotateForFeed ? width : height),
      ...niimbotU16(
        model.rotateForFeed ? (height + 7) ~/ 8 * 8 : (width + 7) ~/ 8 * 8,
      ),
    ];
    _check();
    _printing = true;
    _legacyPages = 0;
    try {
      // Job setup only; no calibration, reset, firmware or power commands.
      if (family == NiimbotPrintFamily.v4) {
        await _ack(0x23, 0x33, [1]);
        await _ack(0x21, 0x31, [model.defaultDensity]);
      } else {
        await _ack(0x21, 0x31, [model.defaultDensity]);
        await _ack(0x23, 0x33, [1]);
      }
      switch (family) {
        case NiimbotPrintFamily.v4:
          await _ack(0x01, 0x02, [...niimbotU16(copies), 0, 0, 0, 0, 0, 1, 0]);
          // Documented one-way status before the V4 page header.
          await write(NiimbotPacket(0xa3, [1]).encode());
          await _ack(0x13, 0x14, [
            ...size,
            ...niimbotU16(copies),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]);
        case NiimbotPrintFamily.b1:
          await _ack(0x01, 0x02, [...niimbotU16(copies), 0, 0, 0, 0, 0]);
          await _ack(0x03, 0x04);
          await _ack(0x13, 0x14, [...size, ...niimbotU16(copies)]);
        case NiimbotPrintFamily.d110:
        case NiimbotPrintFamily.oldD11:
          await _ack(0x01, 0x02);
          await _ack(0x20, 0x30);
          await _ack(0x03, 0x04);
          await _ack(
            0x13,
            0x14,
            family == NiimbotPrintFamily.oldD11 ? size.take(2).toList() : size,
          );
          await _ack(0x15, 0x16, niimbotU16(copies));
        case NiimbotPrintFamily.b21:
        case NiimbotPrintFamily.b21L2b:
          await _ack(0x01, 0x02);
          for (var copy = 0; copy < copies; copy++) {
            if (family == NiimbotPrintFamily.b21L2b) {
              await _pollReady(0x03, 0x04);
            } else {
              await _ack(0x03, 0x04);
            }
            await _ack(0x13, 0x14, size);
            await _sendRows(rows);
            if (family == NiimbotPrintFamily.b21L2b) {
              // End the page first, then query its completion as in L2B's
              // separate printPage / waitForPageFinished operations.
              await _request(0xe3, 0xe4);
              await _pollReady(0xe3, 0xe4);
            } else {
              await _ack(0xe3, 0xe4);
            }
          }
          if (family == NiimbotPrintFamily.b21L2b) {
            await _ack(0xf3, 0xf4);
          } else {
            await _pollReady(0xf3, 0xf4);
          }
          return;
      }
      _lastD11HRow = null;
      _trackD11HRows = model == LabelPrinterModel.d11H;
      await _sendRows(rows);
      // Capture E0 even if it arrives before the page-end ACK.
      _acceptLegacyPageIndex = family == NiimbotPrintFamily.oldD11;
      await _ack(0xe3, 0xe4);
      if (_trackD11HRows &&
          _lastD11HRow != null &&
          _lastD11HRow! < rows.length - 1) {
        throw const LabelPrintException(LabelPrintFailure.rejected);
      }
      if (family == NiimbotPrintFamily.oldD11) {
        await _waitForLegacyCopies(copies);
      } else {
        await _waitForCopies(copies);
      }
      await _ack(0xf3, 0xf4);
    } on Object {
      close();
      rethrow;
    } finally {
      _acceptLegacyPageIndex = false;
      _trackD11HRows = false;
      _printing = false;
    }
  }
}
