/// Microbalance (V300+) and Microbalance Ti (V010+) protocol, published at
/// github.com/DiFluid/difluid-sdk-demo/docs/protocolMicrobalance.md.
library;

import 'dart:typed_data';

import 'package:holybeans/domain/difluid_frame.dart';
import 'package:holybeans/domain/scale_recording.dart';

abstract final class DifluidScaleUuids {
  static const microbalance = '000000ee-0000-1000-8000-00805f9b34fb';
  static const microbalanceTi = '000000dd-0000-1000-8000-00805f9b34fb';
  static const cleartext = '0000aa01-0000-1000-8000-00805f9b34fb';
  static const alternate = '0000ff01-0000-1000-8000-00805f9b34fb';
}

/// Product names, including the Ti's shortened Bluetooth name.
bool isDifluidScaleName(String? name) =>
    name != null &&
    RegExp(r'microbalance|\bmb\s+ti\b', caseSensitive: false).hasMatch(name);

final difluidGetScaleData = difluidFrame(3, 0);
final difluidGetScaleStatus = difluidFrame(3, 5);
final difluidGetScaleUnit = difluidFrame(1, 4);
final difluidScaleTare = difluidFrame(3, 2, [1]);
final difluidScaleTimerClick = difluidFrame(3, 2, [0]);
final difluidScaleTimerPause = difluidFrame(3, 1, [0]);

/// Valid sensor data. Older 12-byte payloads need the separately read unit.
/// Weight and flow use big endian signed integers, time is seconds.
ScaleReading? parseDifluidScaleReading(
  List<int> packet, {
  int? batteryPercent,
  int? legacyUnit,
  bool? timerRunning,
  bool timerAutoStopped = false,
}) {
  final frame = parseDifluidFrame(packet);
  if (frame == null ||
      frame.function != 3 ||
      frame.command != 0 ||
      (frame.data.length != 12 && frame.data.length != 13)) {
    return null;
  }
  final data = frame.data;
  final unit = data.length == 13 ? data[12] : legacyUnit;
  if (unit == null || unit < 0 || unit > 2) return null;
  final bytes = ByteData.sublistView(Uint8List.fromList(data));
  final rawWeight = bytes.getInt32(0);
  final grams = switch (unit) {
    0 => rawWeight / 10,
    1 => rawWeight / 1000 * 28.349523125,
    2 => rawWeight / 10 * 0.06479891,
    _ => throw StateError('Validated weight unit'),
  };
  return ScaleReading(
    grams: grams,
    // The published sensor format expresses flow in tenths of g/s.
    flowGramsPerSecond: bytes.getInt16(4) / 10,
    timerMs: bytes.getUint16(6) * 1000,
    timerRunning: timerRunning,
    timerAutoStopped: timerAutoStopped,
    batteryPercent: batteryPercent,
  );
}

/// Status and battery; ignored if the frame or battery is invalid.
({int state, int battery})? parseDifluidScaleStatus(List<int> packet) {
  final frame = parseDifluidFrame(packet);
  if (frame == null ||
      frame.function != 3 ||
      frame.command != 5 ||
      frame.data.length != 8 ||
      frame.data[1] > 100) {
    return null;
  }
  return (state: frame.data[0], battery: frame.data[1]);
}

/// The current weight unit, read without changing the device's settings.
int? parseDifluidScaleUnit(List<int> packet) {
  final frame = parseDifluidFrame(packet);
  return frame != null &&
          frame.function == 1 &&
          frame.command == 4 &&
          frame.data.length == 1 &&
          frame.data[0] <= 2
      ? frame.data[0]
      : null;
}
