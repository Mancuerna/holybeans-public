import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  ShotCurve curve(List<double> values, {int stepMs = 133}) => ShotCurve(
    timesMs: [for (var i = 0; i < values.length; i++) i * stepMs],
    pressure: values,
    flow: values,
    weight: values,
  );

  test('smoothing removes steps and one-sample dips but keeps the shape', () {
    // A slow ramp reported in 0.1 steps, as stored before.
    final steps = [for (var i = 0; i < 60; i++) 1.2 + (i ~/ 15) * 0.1];
    final smooth = curve(steps).smoothed().flow;
    expect(smooth, hasLength(steps.length));
    for (var i = 1; i < smooth.length; i++) {
      expect(smooth[i], greaterThanOrEqualTo(smooth[i - 1] - 1e-9));
    }
    // Around a step the change is spread over several samples.
    expect(smooth[15] - smooth[14], lessThan(0.05));

    // A one-sample dip on a plateau almost disappears.
    final plateau = [for (var i = 0; i < 40; i++) i == 20 ? 5.9 : 6.0];
    final flat = curve(plateau).smoothed().pressure;
    expect(flat[20], greaterThan(5.98));
    expect(flat.first, closeTo(6.0, 1e-9));

    // Values stay within the original range and times are untouched.
    final shot = curve([0, 0, 9, 9, 9, 0, 0]).smoothed();
    expect(shot.timesMs, [0, 133, 266, 399, 532, 665, 798]);
    expect(shot.pressure.every((value) => value >= 0 && value <= 9), isTrue);
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
