import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/difluid_frame.dart';
import 'package:holybeans/domain/difluid_scale_protocol.dart';

List<int> sensor({
  int weight = 2810,
  int flow = 35,
  int seconds = 93,
  int unit = 0,
  bool legacy = false,
}) {
  final data = ByteData(13)
    ..setInt32(0, weight)
    ..setInt16(4, flow)
    ..setUint16(6, seconds)
    ..setUint32(8, 665520)
    ..setUint8(12, unit);
  return difluidFrame(
    3,
    0,
    data.buffer.asUint8List(0, legacy ? 12 : 13).toList(),
  );
}

void main() {
  test('commands match manufacturer examples; only reads, tare and timer', () {
    expect(difluidGetScaleData, [0xdf, 0xdf, 3, 0, 0, 0xc1]);
    expect(difluidGetScaleStatus, [0xdf, 0xdf, 3, 5, 0, 0xc6]);
    expect(difluidGetScaleUnit, [0xdf, 0xdf, 1, 4, 0, 0xc3]);
    expect(difluidScaleTare, [0xdf, 0xdf, 3, 2, 1, 1, 0xc5]);
    expect(difluidScaleTimerClick, [0xdf, 0xdf, 3, 2, 1, 0, 0xc4]);
    expect(difluidScaleTimerPause, [0xdf, 0xdf, 3, 1, 1, 0, 0xc3]);
  });

  test('official sensor example decodes to 76 grams', () {
    final reading = parseDifluidScaleReading([
      0xdf,
      0xdf,
      3,
      0,
      13,
      0,
      0,
      2,
      0xf8,
      0,
      0,
      0,
      0,
      0,
      0x0a,
      0x27,
      0xb0,
      0,
      0xa9,
    ])!;
    expect(reading.grams, 76);
    expect(reading.timerMs, 0);
  });

  test('signed weight, flow, seconds and battery survive decoding', () {
    final r = parseDifluidScaleReading(sensor(), batteryPercent: 64)!;
    expect(r.grams, 281);
    expect(r.flowGramsPerSecond, 3.5);
    expect(r.timerMs, 93000);
    expect(r.batteryPercent, 64);
    final lifted = parseDifluidScaleReading(sensor(weight: -1200, flow: -25))!;
    expect(lifted.grams, -120);
    expect(lifted.flowGramsPerSecond, -2.5);
  });

  test('ounces and grains are converted without changing scale settings', () {
    expect(
      parseDifluidScaleReading(sensor(weight: 1000, unit: 1))!.grams,
      closeTo(28.349523125, 0.000001),
    );
    expect(
      parseDifluidScaleReading(sensor(weight: 100, unit: 2))!.grams,
      closeTo(0.6479891, 0.000001),
    );
    expect(parseDifluidScaleReading(sensor(unit: 3)), isNull);
    expect(parseDifluidScaleReading(sensor(legacy: true)), isNull);
    expect(
      parseDifluidScaleReading(sensor(legacy: true), legacyUnit: 0)!.grams,
      281,
    );
  });

  test('corrupt, truncated and other device frames are ignored', () {
    final good = sensor();
    expect(parseDifluidScaleReading(good.sublist(0, 18)), isNull);
    expect(parseDifluidScaleReading([...good]..[18] ^= 1), isNull);
    expect(parseDifluidScaleReading(difluidFrame(3, 1, [0])), isNull);
    expect(parseDifluidScaleReading(difluidFrame(3, 0, [1])), isNull);
    expect(parseDifluidFrame([...good]..[4] = 12), isNull);
  });

  test('status and unit replies validate their payloads', () {
    expect(
      parseDifluidScaleStatus(difluidFrame(3, 5, [5, 64, 0, 0, 0, 0, 0, 0])),
      (state: 5, battery: 64),
    );
    expect(
      parseDifluidScaleStatus(difluidFrame(3, 5, [5, 101, 0, 0, 0, 0, 0, 0])),
      isNull,
    );
    expect(parseDifluidScaleUnit(difluidFrame(1, 4, [1])), 1);
    expect(parseDifluidScaleUnit(difluidFrame(1, 4, [3])), isNull);
  });

  test('scale names include Microbalance and MB Ti but exclude R2', () {
    for (final name in [
      'DiFluid Microbalance',
      'Microbalance Ti',
      'MB Ti 001',
    ]) {
      expect(isDifluidScaleName(name), isTrue);
    }
    for (final name in ['DiFluid R2', 'BOOKOO_SC_U', 'DiFluid Omni', null]) {
      expect(isDifluidScaleName(name), isFalse);
    }
  });
}
