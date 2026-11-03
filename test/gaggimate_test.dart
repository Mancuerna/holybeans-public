import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/gaggimate/binary.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';

import 'helpers/gaggimate_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GaggimateShot decode(Uint8List bytes) => decodeGaggimateShot(
    bytes,
    id: '31',
    machineAddress: 'http://gaggimate.local',
  );
  for (final version in [1, 4, 5, 6, 7, 8]) {
    test('v$version decodes times, measured weight and post-shot drips', () {
      final shot = decode(gaggimateLog(version: version));
      expect(shot.profileName, 'Café test');
      expect(shot.timeSeconds, 30);
      expect(shot.yieldGrams, 36.5);
      expect(shot.peakPressureBar, 9);
      expect(shot.temperatureC, 93);
      expect(shot.firstDripSeconds, 4);
      expect(shot.preinfusionSeconds, isNull);
      expect(shot.curve!.timesMs, [0, 4000, 8000, 30000, 32000]);
      expect(shot.curve!.flow, everyElement(1.2)); // scale, not pump's 3 ml/s
      expect(shot.curve!.weight.last, 36.5);
    });
  }
  test('named phases leave preinfusion empty and manually editable', () {
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.preinfusion.text = '12';
    draft.applyGaggimateShot(decode(gaggimateLog()));
    expect(draft.preinfusion.text, isEmpty);
    expect(draft.firstDrip.text, '4');
    draft.preinfusion.text = '6';
    expect(draft.preinfusion.text, '6');
  });
  test('legacy v6 records use ticks despite version number', () {
    expect(
      decode(gaggimateLog(version: 6, legacyV6: true)).curve!.durationMs,
      32000,
    );
  });
  test(
    'no scale never substitutes estimates, supports pressure-only round trip',
    () {
      final shot = decode(gaggimateLog(scale: false));
      expect(shot.yieldGrams, isNull);
      expect(shot.firstDripSeconds, isNull);
      expect(shot.curve!.weight, isEmpty);
      expect(shot.curve!.flow, isEmpty);
      final curve = ShotCurve.fromJson(shot.curve!.toJson());
      expect(curve.pressure, shot.curve!.pressure);
      expect(detectPours(curve), isEmpty);
    },
  );
  test('scale gap omits unreliable curves but keeps final healthy weight', () {
    final shot = decode(gaggimateLog(dropScale: true));
    expect(shot.yieldGrams, 36.5);
    expect(shot.curve!.weight, isEmpty);
  });
  test('zero measured pressure replaces recipe memory and missing weights clear it', () {
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.pressure.text = '9';
    draft.beverage.text = '40';
    draft.dose.text = '18';
    draft.applyGaggimateShot(decode(gaggimateLog(peak: 0, scale: false)));
    expect(draft.pressure.text, '0');
    expect(draft.beverage.text, isEmpty);
    expect(draft.dose.text, '18');
  });
  test('notes fill dose and grind but do not override measured beverage', () {
    final shot = decodeGaggimateShot(
      gaggimateLog(),
      id: '31',
      machineAddress: 'x',
      notes: {
        'doseIn': '18.5',
        'doseOut': '99',
        'grindSetting': '2.1',
        'notes': 'Sweet',
      },
    );
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.applyGaggimateShot(shot);
    expect(draft.dose.text, '18.5');
    expect(draft.grindSetting.text, '2.1');
    expect(draft.notes.text, 'Sweet');
    expect(shot.yieldGrams, 36.5);
  });
  test(
    'index excludes deleted and unfinished records and sorts newest first',
    () {
      expect(decodeGaggimateIndex(gaggimateIndex(count: 2)).map((e) => e.id), [
        '32',
        '31',
      ]);
      expect(decodeGaggimateIndex(gaggimateIndex(flags: 3)), isEmpty);
      expect(decodeGaggimateIndex(gaggimateIndex(flags: 0)), isEmpty);
      expect(() => decodeGaggimateIndex(Uint8List(10)), throwsFormatException);
      final truncated = gaggimateIndex().sublist(0, 150);
      expect(() => decodeGaggimateIndex(truncated), throwsFormatException);
    },
  );
  test('rejects unknown, incomplete, invalid and nonmonotonic recordings', () {
    for (final mutate in <void Function(ByteData)>[
      (b) => b.setUint8(4, 9),
      (b) => b.setUint8(5, 0),
      (b) => b.setUint32(16, 0, Endian.little),
      (b) => b.setUint32(16, 1000, Endian.little),
      (b) => b.setUint32(542, 0, Endian.little),
      (b) => b.setUint8(458, 13),
    ]) {
      final bytes = gaggimateLog();
      mutate(ByteData.sublistView(bytes));
      expect(() => decode(bytes), throwsFormatException);
    }
    expect(() => decode(gaggimateLog().sublist(0, 600)), throwsFormatException);
  });
  test(
    'a disconnected scale at the end cannot supply a final beverage weight',
    () {
      final bytes = gaggimateLog();
      ByteData.sublistView(bytes)
          .setUint16(512 + 4 * 30 + 26, 16, Endian.little);
      expect(decode(bytes).yieldGrams, isNull);
    },
  );
  test(
    'zero final scale weight asks for a manual beverage instead of saving zero',
    () {
      final bytes = gaggimateLog();
      ByteData.sublistView(bytes)
          .setUint16(512 + 4 * 30 + 20, 0, Endian.little);
      expect(decode(bytes).yieldGrams, isNull);
    },
  );
  test('v8 ignores Bluetooth when it is not the active weight source', () {
    final bytes = gaggimateLog();
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < 5; i++) {
      data.setUint16(512 + i * 30 + 26, 4 | (i >= 3 ? 16 : 0), Endian.little);
    }
    final shot = decode(bytes);
    expect(shot.yieldGrams, isNull);
    expect(shot.curve!.weight, isEmpty);
    expect(shot.firstDripSeconds, isNull);
  });
  test('identity distinguishes machines and reset ids', () {
    final a = DateTime(2026);
    final b = DateTime(2027);
    expect(
      gaggimateExternalId('a', '31', a),
      isNot(gaggimateExternalId('b', '31', a)),
    );
    expect(
      gaggimateExternalId('a', '31', a),
      isNot(gaggimateExternalId('a', '31', b)),
    );
  });
}
