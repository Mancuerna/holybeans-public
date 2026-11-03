import 'dart:math' as math;

import 'package:holybeans/domain/scale_recording.dart';

// Protocol reference and captured fixtures: aioacaia (MIT, Josef Zweck).
// See assets/licenses/aioacaia.txt and docs/reviews/2026-10-27-acaia.md.
abstract final class AcaiaUuids {
  static const service = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static const notify = '49535343-1e4d-4bd9-ba61-23c647249616';
  static const write = '49535343-8841-43f4-a8d4-ecbe34729bb3';
  static const classic = '00002a80-0000-1000-8000-00805f9b34fb';
}

bool isAcaiaScaleName(String? name) {
  final value = name?.toUpperCase() ?? '';
  return ['ACAIA', 'LUNAR', 'PEARL', 'PYXIS'].any(value.startsWith) ||
      value == 'PROCHBT001';
}

List<int> acaiaFrame(int command, List<int> body) {
  var even = 0;
  var odd = 0;
  for (var i = 0; i < body.length; i++) {
    if (i.isEven) {
      even += body[i];
    } else {
      odd += body[i];
    }
  }
  return [0xef, 0xdd, command, ...body, even & 255, odd & 255];
}

const acaiaAndroidWakeUp = <int>[0, 1];
List<int> acaiaIdentify({required bool classic}) =>
    acaiaFrame(11, (classic ? '---------------' : '012345678901234').codeUnits);
final acaiaSubscribe = acaiaFrame(12, [9, 0, 1, 1, 2, 2, 5, 3, 4]);
final acaiaHeartbeat = acaiaFrame(0, [2, 0]);
final acaiaReadSettings = acaiaFrame(6, List.filled(16, 0));

List<List<int>> acaiaCommands(ScaleCommand command) => switch (command) {
  ScaleCommand.tare => [
    acaiaFrame(4, [0]),
  ],
  ScaleCommand.startTimer => [
    acaiaFrame(13, [0, 0]),
  ],
  ScaleCommand.stopTimer => [
    acaiaFrame(13, [0, 2]),
  ],
  ScaleCommand.resetTimer => [
    acaiaFrame(13, [0, 2]),
    acaiaFrame(13, [0, 1]),
  ],
  ScaleCommand.tareAndStartTimer => [
    acaiaFrame(13, [0, 2]),
    acaiaFrame(13, [0, 1]),
    acaiaFrame(4, [0]),
    acaiaFrame(13, [0, 0]),
  ],
};

/// One connection's framed notification stream. Never guesses units or stops
/// a brew merely because a scale clock temporarily stops advancing.
class AcaiaDecoder {
  final _buffer = <int>[];
  double? _weight;
  int? _unit;
  int? _battery;
  int _timer = 0;
  bool _running = false;
  bool _freshWeight = false;
  double _flow = 0;
  final _weights = <(int, double)>[];
  bool get hasSettings => _unit != null;
  bool get ready => hasSettings && _weight != null;

  void commanded(ScaleCommand command) {
    if (command == ScaleCommand.tare ||
        command == ScaleCommand.tareAndStartTimer) {
      _weights.clear();
      _flow = 0;
    }
    switch (command) {
      case ScaleCommand.startTimer:
        _running = true;
      case ScaleCommand.stopTimer:
        _running = false;
      case ScaleCommand.resetTimer:
        _timer = 0;
        _running = false;
      case ScaleCommand.tareAndStartTimer:
        _timer = 0;
        _running = true;
      case ScaleCommand.tare:
        break;
    }
  }

  List<ScaleReading> add(List<int> bytes, {int? elapsedMs}) {
    _buffer.addAll(bytes);
    final readings = <ScaleReading>[];
    while (_buffer.length >= 4) {
      if (_buffer[0] != 0xef ||
          _buffer[1] != 0xdd ||
          ![8, 12].contains(_buffer[2]) ||
          _buffer[3] < 2 ||
          _buffer[3] > 64) {
        _buffer.removeAt(0);
        continue;
      }
      final length = _buffer[3] + 5;
      if (_buffer.length < length) break;
      final frame = _buffer.sublist(0, length);
      final checked = acaiaFrame(frame[2], frame.sublist(3, length - 2));
      if (frame[length - 2] != checked[length - 2] ||
          frame.last != checked.last) {
        _buffer.removeAt(0);
        continue;
      }
      _buffer.removeRange(0, length);
      var changed = false;
      _freshWeight = false;
      if (frame[2] == 8 && length >= 12) {
        // Settings are read, never changed. The weight precision is separate
        // from the display unit, so ounce readings must be converted to grams.
        final previousUnit = _unit;
        _unit = switch (frame[5]) {
          2 => 2,
          5 => 5,
          _ => null,
        };
        if (_unit != previousUnit) _weights.clear();
        final battery = frame[4] & 0x7f;
        _battery = battery <= 100 ? battery : null;
      } else if (frame[2] == 12) {
        changed = _records(frame.sublist(4, length - 2));
      }
      if (changed && ready) {
        final grams = _weight! * (_unit == 5 ? 28.349523125 : 1);
        if (_freshWeight && elapsedMs != null) _updateFlow(elapsedMs, grams);
        readings.add(
          ScaleReading(
            grams: grams,
            flowGramsPerSecond: _flow,
            timerMs: _timer,
            timerRunning: _running,
            batteryPercent: _battery,
          ),
        );
      }
    }
    return readings;
  }

  void _updateFlow(int ms, double grams) {
    if (_weights.isNotEmpty &&
        (ms < _weights.last.$1 || grams < _weights.last.$2 - 1)) {
      _weights.clear();
      _flow = 0;
    }
    while (_weights.isNotEmpty && ms - _weights.first.$1 > 1000) {
      _weights.removeAt(0);
    }
    if (_weights.isNotEmpty && ms - _weights.first.$1 >= 200) {
      _flow = math.max(
        0,
        (grams - _weights.first.$2) * 1000 / (ms - _weights.first.$1),
      );
    } else if (_weights.isEmpty) {
      _flow = 0;
    }
    if (_weights.isEmpty || ms > _weights.last.$1) _weights.add((ms, grams));
  }

  bool _records(List<int> data) {
    var changed = false;
    var i = 0;
    while (i < data.length) {
      final tag = data[i++];
      final width = switch (tag) {
        5 => 6,
        6 => 1,
        7 => 3,
        8 => 1,
        11 => 2,
        _ => 0,
      };
      if (width == 0 || i + width > data.length) break;
      switch (tag) {
        case 5:
          _freshWeight = true;
          final precision = data[i + 4];
          if (precision < 1 || precision > 4) return false;
          _weight = (data[i] + (data[i + 1] << 8)) / math.pow(10, precision);
          if (data[i + 5] & 2 != 0) _weight = -_weight!;
          changed = true;
        case 6:
          if (data[i] <= 100) _battery = data[i];
        case 7:
          if (data[i + 1] >= 60 || data[i + 2] >= 10) return false;
          final next = data[i] * 60000 + data[i + 1] * 1000 + data[i + 2] * 100;
          // Clock samples can arrive after Stop/Reset or advance in an
          // automatic mode. They are measurements, not a Start button press.
          // Only explicit controls (received or commanded) change _running.
          _timer = next;
          changed = true;
        case 8:
          switch (data[i]) {
            case 8:
              _running = true;
            case 9:
              _timer = 0;
              _running = false;
            case 10:
              _running = false;
          }
          changed = true;
      }
      i += width;
    }
    // A button may precede an attached timer: the explicit button wins.
    for (var j = 0; j + 1 < data.length;) {
      final tag = data[j];
      final width = switch (tag) {
        5 => 6,
        6 => 1,
        7 => 3,
        8 => 1,
        11 => 2,
        _ => 0,
      };
      if (width == 0 || j + width >= data.length) break;
      if (tag == 8 && (data[j + 1] == 9 || data[j + 1] == 10)) _running = false;
      j += width + 1;
    }
    return changed;
  }
}
