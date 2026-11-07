import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/timemore_dot_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

bool isTimemoreDotName(String? name) =>
    RegExp(
      r'^(TIMEMORE[ _-]?)?(DOT|TES017)(?:$|[ _?-])',
      caseSensitive: false,
    ).hasMatch(name?.trim() ?? '') ||
    (name ?? '').toUpperCase().contains('BLACK MIRROR DOT');

class DotUuids {
  static final service = BleUuidParser.string('fff0');
  static final notify = BleUuidParser.string('fff1');
  static final write = BleUuidParser.string('fff2');
  static final info = BleUuidParser.string('180a');
  static final model = BleUuidParser.string('2a24');
  static final maker = BleUuidParser.string('2a29');
  static final firmware = BleUuidParser.string('2a26');
}

class TimemoreDotConnection {
  TimemoreDotConnection({
    required this.id,
    required this.withResponse,
    this.trace,
  }) {
    _decoder = _createDecoder();
  }

  final String id;
  final bool withResponse;
  final BleTrace? trace;
  late DotDecoder _decoder;
  final _state = DotState();
  bool _closed = false;
  bool _identified = false;
  bool _uncertainCommand = false;
  Future<bool> _commands = Future.value(true);
  Completer<bool>? _ack;
  int? _ackCommand;
  int? _ackTimerState;

  void _log(String event, Map<String, Object?> data) =>
      emitBleTrace(trace, 'dot.$event', data);

  DotDecoder _createDecoder({bool allowReservedZeroCrc = false}) => DotDecoder(
    allowReservedZeroCrc: allowReservedZeroCrc,
    onRejected: (reason, bytes) {
      _log('rejected', {'reason': reason, 'bytes': bleHex(bytes)});
    },
  );

  void _checkOpen() {
    if (_closed) throw StateError('Dot connection closed');
  }

  Future<String> _readInfo(String characteristic) async {
    _checkOpen();
    final bytes = await UniversalBle.read(
      id,
      DotUuids.info,
      characteristic,
      timeout: const Duration(seconds: 5),
    );
    _checkOpen();
    final value = utf8.decode(bytes).replaceAll('\u0000', '').trim();
    _log('identity', {
      'characteristic': characteristic,
      'value': value,
      'bytes': bleHex(bytes),
    });
    return value;
  }

  Future<void> start() async {
    // FFF0 is shared by unrelated devices. Never send protocol bytes until
    // the read-only standard identity confirms this exact product.
    final model = await _readInfo(DotUuids.model);
    final maker = await _readInfo(DotUuids.maker);
    if (model.toUpperCase() != 'TES017' || maker.toUpperCase() != 'TIMEMORE') {
      throw StateError('Not a verified Timemore DOT TES017: $maker / $model');
    }
    String? firmware;
    try {
      firmware = await _readInfo(DotUuids.firmware);
    } on Object catch (error) {
      _log('firmware.unavailable', {'error': '$error'});
    }
    _checkOpen();
    _log('bond.start', {});
    if (await UniversalBle.isPaired(id, timeout: const Duration(seconds: 5)) !=
        true) {
      _checkOpen();
      await UniversalBle.pair(id, timeout: const Duration(seconds: 30));
    }
    _checkOpen();
    _log('bond.ok', {});
    final reservedZeroCrc = firmware == 'v1.0.4';
    _decoder = _createDecoder(allowReservedZeroCrc: reservedZeroCrc);
    _log('crc.policy', {
      'firmware': firmware,
      'allowReservedZero': reservedZeroCrc,
    });
    _identified = true;
    for (final query in [DotQuery.unit, DotQuery.battery, DotQuery.timer]) {
      await _write(dotQuery(query), 'read.${query.name}');
    }
    // Replies can arrive after the writes complete. Until units are known,
    // keep receiving notifications without publishing fabricated grams.
    _log('ready', {'unit': _state.unit, 'battery': _state.battery});
  }

  Iterable<ScaleReading> parse(Uint8List packet) sync* {
    for (final frame in _decoder.add(packet)) {
      _log('frame', {
        'operation': frame.operation,
        'command': frame.command,
        'payload': bleHex(frame.payload),
        'identified': _identified,
        'crc': frame.crcVerified ? 'verified' : 'reservedZero',
      });
      if (!_identified || _closed) continue;
      if (frame.operation == 3 &&
          frame.command == _ackCommand &&
          frame.payload.length == 1) {
        if (_ack case final ack? when !ack.isCompleted) {
          // The ACK carries success, not the new timer state. Apply the
          // acknowledged request before parsing another coalesced weight frame.
          if (frame.payload[0] == 1 && _ackTimerState != null) {
            _state.running = _ackTimerState == 1;
          }
          ack.complete(frame.payload[0] == 1);
        }
      }
      final reading = _state.accept(frame);
      if (reading != null) {
        yield reading;
      } else if (frame.operation == 1 && frame.command == 1) {
        _log('reading.skipped', {
          'unit': _state.unit,
          'payload': bleHex(frame.payload),
        });
      }
    }
  }

  Future<void> _write(Uint8List bytes, String purpose) async {
    _checkOpen();
    if (!_identified) throw StateError('Dot identity unverified');
    final watch = Stopwatch()..start();
    _log('write', {
      'purpose': purpose,
      'bytes': bleHex(bytes),
      'withResponse': withResponse,
    });
    try {
      await UniversalBle.write(
        id,
        DotUuids.service,
        DotUuids.write,
        bytes,
        withoutResponse: !withResponse,
        timeout: const Duration(seconds: 5),
      );
      _checkOpen();
      _log('write.ok', {
        'purpose': purpose,
        'elapsedMs': watch.elapsedMilliseconds,
      });
    } on Object catch (error) {
      _log('write.error', {
        'purpose': purpose,
        'elapsedMs': watch.elapsedMilliseconds,
        'error': '$error',
      });
      rethrow;
    }
  }

  Future<bool> send(ScaleCommand command) =>
      _commands = _commands.then((_) async {
        if (_closed || !_identified || _uncertainCommand) {
          _log('command.blocked', {'reconnectRequired': _uncertainCommand});
          return false;
        }
        _log('command', {'command': command.name});
        try {
          for (final bytes in dotCommands(command)) {
            _checkOpen();
            final ack = _ack = Completer<bool>();
            _ackCommand = bytes[3];
            _ackTimerState = bytes[3] == 2 ? bytes[6] : null;
            await _write(bytes, command.name);
            final ok = await ack.future.timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                _uncertainCommand = true;
                _log('ack.timeout', {'command': command.name});
                return false;
              },
            );
            _log('ack.result', {'command': command.name, 'ok': ok});
            if (!ok || _closed) return false;
          }
          return true;
        } on Object catch (error) {
          _uncertainCommand = true;
          _log('command.error', {'command': command.name, 'error': '$error'});
          return false;
        } finally {
          _ack = null;
          _ackCommand = null;
          _ackTimerState = null;
        }
      });

  void close() {
    _closed = true;
    if (_ack case final ack? when !ack.isCompleted) ack.complete(false);
  }
}
