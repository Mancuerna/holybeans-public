import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/acaia_protocol.dart';
import 'package:holybeans/domain/scale_recording.dart';

List<int> hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
List<int> event(List<int> records) =>
    acaiaFrame(12, [records.length + 1, ...records]);
final settings = hex('efdd08095d020201000101000d60');
final capturedWeight = hex('efdd0c0c05df060000010007000002f30d');

void main() {
  late AcaiaDecoder decoder;
  setUp(() {
    decoder = AcaiaDecoder();
    decoder.add(settings);
  });
  test('real captured Pearl weight and attached timer', () {
    final r = decoder.add(capturedWeight).single;
    expect(r.grams, 175.9);
    expect(r.timerMs, 200);
    expect(r.batteryPercent, 93);
    expect(r.timerRunning, isFalse);
  });
  test('clock samples never restart after Stop or Reset', () {
    decoder.add(capturedWeight);
    for (final command in [ScaleCommand.stopTimer, ScaleCommand.resetTimer]) {
      decoder.commanded(ScaleCommand.startTimer);
      decoder.commanded(command);
      for (final seconds in [0, 1, 2, 3, 0, 4]) {
        final r = decoder.add(event([7, 0, seconds, 0])).single;
        expect(r.timerMs, seconds * 1000);
        expect(r.timerRunning, isFalse);
      }
      expect(decoder.add(event([8, 8])).single.timerRunning, isTrue);
      decoder.add(event([8, 10]));
      expect(decoder.add(event([7, 0, 5, 0])).single.timerRunning, isFalse);
      decoder.add(event([8, 9]));
      expect(decoder.add(event([7, 0, 6, 0])).single.timerRunning, isFalse);
    }
  });
  test('all split points and concatenated frames retain readings', () {
    for (var split = 1; split < capturedWeight.length; split++) {
      final d = AcaiaDecoder()..add(settings);
      expect(d.add(capturedWeight.sublist(0, split)), isEmpty);
      final rs = d.add([...capturedWeight.sublist(split), ...capturedWeight]);
      expect(rs.map((r) => r.grams), [175.9, 175.9]);
    }
  });
  test('checksum noise and oversized lengths recover at next frame', () {
    final bad = [...capturedWeight];
    bad[bad.length - 1] ^= 1;
    expect(
      decoder
          .add([1, 2, 0xef, 0xdd, 12, 255, ...bad, ...capturedWeight])
          .single
          .grams,
      175.9,
    );
  });
  test('unknown units never become grams and ounces are converted', () {
    final d = AcaiaDecoder();
    expect(d.add(capturedWeight), isEmpty);
    d.add(acaiaFrame(8, [9, 93, 5, 2, 1, 0, 1, 1, 0]));
    expect(
      d.add(event([5, 100, 0, 0, 0, 2, 0])).single.grams,
      closeTo(28.349523125, 0.000001),
    );
    d.add(acaiaFrame(8, [9, 93, 99, 2, 1, 0, 1, 1, 0]));
    expect(d.add(capturedWeight), isEmpty);
  });
  test('negative weights and all documented precision factors', () {
    for (final (precision, expected) in [
      (1, -175.9),
      (2, -17.59),
      (3, -1.759),
      (4, -0.1759),
    ]) {
      expect(
        decoder.add(event([5, 0xdf, 6, 0, 0, precision, 2])).single.grams,
        expected,
      );
    }
    expect(decoder.add(event([5, 0xdf, 6, 0, 0, 0, 0])), isEmpty);
  });
  test('real stop button wins over attached advancing timer', () {
    decoder.add(capturedWeight);
    final r = decoder.add(event(hex('080a0527020000010107000907'))).single;
    expect(r.grams, 55.1);
    expect(r.timerMs, 9700);
    expect(r.timerRunning, isFalse);
    expect(decoder.add(event([11, 0, 224, 8, 8])).single.timerRunning, isTrue);
    expect(decoder.add(event([8, 9])).single.timerMs, 0);
  });
  test(
    'stagnant timer never implies stop; bare buttons need a weight first',
    () {
      expect(decoder.add(event([8, 8])), isEmpty);
      final first = decoder.add(capturedWeight).single;
      final next = decoder.add(capturedWeight).single;
      expect(first.timerRunning, isTrue);
      expect(next.timerRunning, isTrue);
      expect(decoder.add(event([8, 10])).single.timerRunning, isFalse);
    },
  );
  test('flow derives from timed weights and resets on tare or a long gap', () {
    List<int> weight(int tenths) =>
        event([5, tenths & 255, tenths >> 8, 0, 0, 1, 0]);
    expect(decoder.add(weight(0), elapsedMs: 0).single.flowGramsPerSecond, 0);
    expect(
      decoder.add(weight(10), elapsedMs: 200).single.flowGramsPerSecond,
      5,
    );
    expect(
      decoder.add(weight(20), elapsedMs: 400).single.flowGramsPerSecond,
      5,
    );
    decoder.commanded(ScaleCommand.tare);
    expect(decoder.add(weight(0), elapsedMs: 600).single.flowGramsPerSecond, 0);
    expect(
      decoder.add(weight(20), elapsedMs: 2600).single.flowGramsPerSecond,
      0,
    );
  });
  test('outgoing frames match documented public implementation bytes', () {
    expect(acaiaCommands(ScaleCommand.tare).single, hex('efdd04000000'));
    expect(
      acaiaCommands(ScaleCommand.startTimer).single,
      hex('efdd0d00000000'),
    );
    expect(acaiaCommands(ScaleCommand.stopTimer).single, hex('efdd0d00020002'));
    expect(acaiaCommands(ScaleCommand.resetTimer).last, hex('efdd0d00010001'));
    expect(
      acaiaIdentify(classic: false),
      hex('efdd0b3031323334353637383930313233349a6d'),
    );
    expect(acaiaHeartbeat, hex('efdd0002000200'));
  });
}
