import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/pressure_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  ShotCurve curve(List<double> values, {int stepMs = 133}) => ShotCurve(
    timesMs: [for (var i = 0; i < values.length; i++) i * stepMs],
    pressure: values,
    flow: values,
    weight: values,
  );

  test('display keeps narrow pressure peaks and all weight measurements', () {
    final original = curve([0, 0, 6.6, 0, 0], stepMs: 50);
    final saved = original.toJson();
    final shown = original.smoothed();
    expect(shown.pressure, same(original.pressure));
    expect(shown.weight, same(original.weight));
    expect(shown.timesMs, same(original.timesMs));
    expect(shown.maxOf(CurveSeries.pressure), 6.6);
    expect(original.toJson(), saved);
  });

  test(
    'short flow window retains at least 95 percent of a two-second peak',
    () {
      final original = curve([
        for (var i = 0; i <= 200; i++) 6.6 * (1 - (i - 100).abs() / 100),
      ], stepMs: 10);
      final shown = original.smoothed();
      expect(shown.maxOf(CurveSeries.flow), closeTo(6.27, 1e-10));
      expect(shown.flow.indexOf(shown.maxOf(CurveSeries.flow)), 100);
      expect(shown.maxOf(CurveSeries.pressure), 6.6);
    },
  );

  test(
    'flow filtering has bounded reach and keeps endpoints and linear ramps',
    () {
      final ramp = curve([for (var i = 0; i <= 60; i++) i / 10], stepMs: 10);
      final shown = ramp.smoothed();
      for (var i = 0; i < ramp.flow.length; i++) {
        expect(shown.flow[i], closeTo(ramp.flow[i], 1e-10));
      }
      final step = curve([
        for (var i = 0; i <= 60; i++) i < 30 ? 0 : 6,
      ], stepMs: 10);
      final filtered = step.smoothed();
      expect(filtered.flow.take(20), everyElement(0));
      for (final value in filtered.flow.skip(40)) {
        expect(value, closeTo(6, 1e-10));
      }
      expect(filtered.flow.first, step.flow.first);
      expect(filtered.flow.last, step.flow.last);
      expect(filtered.flow[30], greaterThan(0));
      expect(filtered.flow[30], lessThan(6));
      expect(filtered.pressure, step.pressure);
    },
  );

  test('adding pressure timestamps cannot change filtered scale values', () {
    final original = ShotCurve(
      timesMs: [for (var t = 0; t <= 4000; t += 100) t],
      flow: [
        for (var t = 0; t <= 4000; t += 100)
          t <= 2000 ? t / 500 : (4000 - t) / 500,
      ],
      weight: [for (var t = 0; t <= 4000; t += 100) t / 500],
    );
    final pressure = PressureRecording();
    for (var t = 1901; t < 2100; t++) {
      pressure.add(t, 5);
    }
    final combined = pressure.addTo(original).smoothed();
    final shown = original.smoothed();
    for (var i = 0; i < original.timesMs.length; i++) {
      final j = combined.indexAt(original.timesMs[i]);
      expect(combined.flow[j], closeTo(shown.flow[i], 1e-10));
      expect(combined.weight[j], original.weight[i]);
    }
  });

  test('missing flow and pressure series remain absent', () {
    final pressureOnly = ShotCurve(
      timesMs: [0, 50, 100],
      pressure: [0, 6.6, 0],
      flow: [],
      weight: [],
    );
    expect(pressureOnly.smoothed(), same(pressureOnly));
    final scale = ShotCurve(
      timesMs: [0, 50, 100],
      flow: [0, 6, 0],
      weight: [0, 1, 2],
    );
    expect(scale.smoothed().pressure, isEmpty);
  });

  test('short curves are left as they are', () {
    final short = curve([1, 2]);
    expect(identical(short.smoothed(), short), isTrue);
  });

  test('axis ticks are round and reach the maximum', () {
    expect(axisTicks(10.6), [0, 2, 4, 6, 8, 10, 12]);
    expect(axisTicks(9.2), [0, 2, 4, 6, 8, 10]);
    expect(axisTicks(7.2), [0, 2, 4, 6, 8]);
    expect(axisTicks(42.4), [0, 10, 20, 30, 40, 50]);
    expect(axisTicks(34.4), [0, 10, 20, 30, 40]);
    expect(axisTicks(1), [0, 0.2, 0.4, 0.6, 0.8, 1]);
    expect(axisTicks(0), isEmpty);
  });

  test('range ticks are round inside ranges that need not start at zero', () {
    expect(rangeTicks(0, 22.8), [0, 5, 10, 15, 20]);
    expect(rangeTicks(-4.2, 18.6), [0, 5, 10, 15]);
    expect(rangeTicks(-6, 14), [-5, 0, 5, 10]);
    expect(rangeTicks(3, 3), isEmpty);
  });

  test('time ticks fall on round clock times', () {
    expect(timeTicks(226), [0, 60, 120, 180]);
    expect(timeTicks(151), [0, 60, 120]);
    expect(timeTicks(140), [0, 30, 60, 90, 120]);
    expect(timeTicks(28), [0, 10, 20]);
    expect(timeTicks(0), isEmpty);
  });
}
