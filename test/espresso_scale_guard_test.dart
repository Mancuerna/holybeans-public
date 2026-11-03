import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/espresso_scale_guard.dart';
import 'package:holybeans/domain/scale_recording.dart';

void main() {
  test('discards a two-reading load spike and its delayed native flow', () {
    final guard = EspressoScaleGuard();
    final recording = WeightRecording();
    for (final (time, grams, flow) in [
      (20390, 47.2, 1.43),
      (20566, 47.2, 1.07),
      (20777, 252.0, 135.95),
      (20989, 206.0, 4.63),
      (21168, 47.9, -165.52),
      (21300, 48.0, -40.0),
      (22100, 48.2, 0.3),
    ]) {
      final reading = guard.add(
        time,
        ScaleReading(grams: grams, flowGramsPerSecond: flow),
      );
      if (reading != null) recording.add(time, reading);
    }
    expect(recording.curve!.timesMs, [20390, 20566, 21168, 21300, 22100]);
    expect(recording.curve!.weight, [47.2, 47.2, 47.9, 48, 48.2]);
    expect(recording.curve!.flow[2], closeTo(0.7 / 0.602, 0.0001));
    expect(recording.curve!.flow.last, 0.3);
    expect(recording.peakGrams, 48.2);
  });

  test('retains native flow, noise, timer state and a quick normal rise', () {
    final guard = EspressoScaleGuard();
    guard.add(0, const ScaleReading(grams: 0));
    final reading = guard.add(
      150,
      const ScaleReading(
        grams: 15,
        flowGramsPerSecond: 20,
        timerMs: 150,
        timerRunning: true,
        batteryPercent: 85,
      ),
    )!;
    expect(reading.grams, 15);
    expect(reading.flowGramsPerSecond, 20);
    expect(reading.timerMs, 150);
    expect(reading.timerRunning, isTrue);
    expect(reading.batteryPercent, 85);
    expect(guard.add(300, const ScaleReading(grams: 14.8))!.grams, 14.8);
  });

  test('a sustained new load is confirmed and recording can continue', () {
    final guard = EspressoScaleGuard();
    guard.add(0, const ScaleReading(grams: 0));
    expect(guard.add(100, const ScaleReading(grams: 80)), isNull);
    expect(guard.add(350, const ScaleReading(grams: 80.2)), isNull);
    expect(guard.add(600, const ScaleReading(grams: 80.1))!.grams, 80.1);
    expect(guard.add(800, const ScaleReading(grams: 81))!.grams, 81);
  });

  test(
    'close notifications can still drive first-drip and timer detection',
    () {
      final guard = EspressoScaleGuard();
      guard.add(0, const ScaleReading(grams: 0));
      expect(guard.add(0, const ScaleReading(grams: 0.4))!.grams, 0.4);
      expect(guard.add(0, const ScaleReading(grams: 1.2))!.grams, 1.2);
    },
  );

  test('a changing held load cannot time out into the recording', () {
    final guard = EspressoScaleGuard();
    guard.add(0, const ScaleReading(grams: 40));
    for (var time = 100; time <= 3100; time += 300) {
      expect(guard.add(time, const ScaleReading(grams: 200)), isNull);
      // Move the candidate enough that each confirmation must start over.
      expect(guard.add(time + 100, const ScaleReading(grams: 300)), isNull);
    }
    expect(guard.add(3300, const ScaleReading(grams: 40.5))!.grams, 40.5);
  });

  test('removing the cup before Stop preserves accepted beverage weight', () {
    final guard = EspressoScaleGuard();
    final recording = WeightRecording();
    for (final (time, grams) in [
      (0, 0.0),
      (1000, 30.0),
      (2000, 36.4),
      (2100, -310.0),
      (2350, -310.0),
      (2600, -310.0),
    ]) {
      final reading = guard.add(time, ScaleReading(grams: grams));
      if (reading != null) recording.add(time, reading);
    }
    expect(recording.peakGrams, 36.4);
    expect(recording.curve!.flow.last, 0);
  });

  test('rejects invalid or old weight and resets pending loads', () {
    final guard = EspressoScaleGuard();
    expect(guard.add(-1, const ScaleReading(grams: 0)), isNull);
    expect(guard.add(0, const ScaleReading(grams: double.nan)), isNull);
    guard.add(100, const ScaleReading(grams: 40));
    expect(guard.add(99, const ScaleReading(grams: 200)), isNull);
    expect(guard.add(100, const ScaleReading(grams: 200)), isNull);
    expect(guard.add(200, const ScaleReading(grams: 200)), isNull);
    guard.clear();
    expect(guard.add(0, const ScaleReading(grams: 0))!.grams, 0);
    expect(guard.add(100, const ScaleReading(grams: 1))!.flowGramsPerSecond, 0);
  });
}
