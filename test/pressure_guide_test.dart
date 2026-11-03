import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';

ShotCurve curve(List<int> times, List<double> bars) =>
    ShotCurve(timesMs: times, pressure: bars, flow: const [], weight: const []);

void main() {
  test('interpolates irregular samples on the original timeline', () {
    final guide = PressureGuide.fromCurve(curve([500, 1500, 4000], [1, 9, 6]))!;
    expect(guide.targetAt(0), isNull);
    expect(guide.targetAt(500), 1);
    expect(guide.targetAt(1000), 5);
    expect(guide.targetAt(2750), 7.5);
    expect(guide.targetAt(4000), 6);
    expect(guide.targetAt(4001), isNull);
  });
  test('rejects empty, flat zero, unordered and invalid pressure', () {
    for (final value in [
      curve([], []),
      curve([0], [9]),
      curve([0, 100], [0, 0]),
      curve([0, 0], [1, 2]),
      curve([100, 0], [1, 2]),
      curve([-1, 100], [1, 2]),
      curve([0, 100], [1, double.nan]),
      curve([0, 100], [-1, 2]),
      curve([0, 100], [1, 31]),
      curve([0, 100], []),
    ]) {
      expect(PressureGuide.fromCurve(value), isNull);
    }
  });
  test('reference is independent of later source mutations', () {
    final times = [0, 1000];
    final bars = [2.0, 8.0];
    final guide = PressureGuide.fromCurve(curve(times, bars))!;
    times[1] = 500;
    bars[1] = 4;
    expect(guide.targetAt(500), 5);
    expect(() => guide.bars[0] = 8, throwsUnsupportedError);
  });
}
