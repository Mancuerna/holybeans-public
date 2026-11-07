import 'dart:typed_data';

import 'package:holybeans/domain/scale_recording.dart';

// Timemore's open-scale-protocol v1.0.3. See docs/DEVICES.md.
int dotCrc(Iterable<int> bytes) {
  var crc = 0xffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xa001 : crc >> 1;
    }
  }
  return crc;
}

Uint8List _frame(int operation, int command, List<int> payload) {
  final bytes = [0xa5, 0x5a, operation, command, 0, payload.length, ...payload];
  final crc = dotCrc(bytes);
  return Uint8List.fromList([...bytes, crc >> 8, crc & 0xff]);
}

enum DotQuery { timer, battery, unit }

Uint8List dotQuery(DotQuery query) => _frame(2, switch (query) {
  DotQuery.timer => 2,
  DotQuery.battery => 5,
  DotQuery.unit => 6,
}, const []);

List<Uint8List> dotCommands(ScaleCommand command) => switch (command) {
  ScaleCommand.tare => [_frame(3, 0x0d, const [])],
  ScaleCommand.startTimer => [
    _frame(3, 2, const [1]),
  ],
  ScaleCommand.stopTimer => [
    _frame(3, 2, const [2]),
  ],
  ScaleCommand.resetTimer => [
    _frame(3, 2, const [3]),
  ],
  ScaleCommand.tareAndStartTimer => [
    _frame(3, 0x0d, const []),
    _frame(3, 2, const [3]),
    _frame(3, 2, const [1]),
  ],
};

class DotFrame {
  const DotFrame(
    this.operation,
    this.command,
    this.payload, {
    this.crcVerified = true,
  });
  final int operation;
  final int command;
  final Uint8List payload;
  final bool crcVerified;
}

class DotDecoder {
  DotDecoder({this.onRejected, this.allowReservedZeroCrc = false});
  final void Function(String reason, List<int> bytes)? onRejected;
  // TES017 v1.0.4 uses 00 00 in the reserved CRC field. Opt in only after
  // reading the device identity/firmware; other CRC values remain checked.
  final bool allowReservedZeroCrc;
  final _buffer = <int>[];

  // Frames can span notifications or share one. The maximum keeps a corrupt
  // length from retaining an unbounded stream. Each iteration consumes input.
  List<DotFrame> add(List<int> bytes) {
    final frames = <DotFrame>[];
    for (final byte in bytes) {
      _buffer.add(byte);
      while (_buffer.length >= 2) {
        if (_buffer[0] != 0xa5 || _buffer[1] != 0x5a) {
          _buffer.removeAt(0);
          continue;
        }
        if (_buffer.length < 6) break;
        final length = (_buffer[4] << 8) | _buffer[5];
        if (length > 64) {
          onRejected?.call('length', List.of(_buffer));
          _buffer.removeAt(0);
          continue;
        }
        final total = length + 8;
        if (_buffer.length < total) break;
        final raw = _buffer.sublist(0, total);
        final crc = (raw[total - 2] << 8) | raw[total - 1];
        final crcVerified = dotCrc(raw.take(total - 2)) == crc;
        if (!crcVerified && !(allowReservedZeroCrc && crc == 0)) {
          onRejected?.call('crc', raw);
          _buffer.removeAt(0);
          continue;
        }
        frames.add(
          DotFrame(
            raw[2],
            raw[3],
            Uint8List.fromList(raw.sublist(6, total - 2)),
            crcVerified: crcVerified,
          ),
        );
        _buffer.removeRange(0, total);
      }
    }
    return frames;
  }
}

class DotState {
  int? unit;
  int? battery;
  bool? running;

  ScaleReading? accept(DotFrame frame) {
    final data = frame.payload;
    if (frame.operation != 1 && frame.operation != 2) return null;
    switch (frame.command) {
      case 6:
        // Invalidate previous units on an unrecognised unit response.
        unit = data.length == 1 && data[0] <= 1 ? data[0] : null;
      case 5:
        battery = data.length == 2 && data[1] <= 100 ? data[1] : null;
      case 2:
        running = data.length == 1 && data[0] >= 1 && data[0] <= 3
            ? data[0] == 1
            : null;
      case 1:
        if (frame.operation != 1 || data.length != 9 || unit != 0) return null;
        final value = ByteData.sublistView(data);
        final seconds = value.getUint16(6);
        if (data[8] != 0 || seconds > 3599) return null;
        // TES017 v1.0.4 reports tenths of a gram. Ounces are not converted.
        return ScaleReading(
          grams: value.getInt32(0) / 10,
          flowGramsPerSecond: value.getInt16(4) / 10,
          timerMs: seconds * 1000,
          timerRunning: running,
          batteryPercent: battery,
        );
    }
    return null;
  }
}
