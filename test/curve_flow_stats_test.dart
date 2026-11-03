import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/pressure_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  ShotCurve curve(List<int> t, List<double> f, {List<double>? w}) =>
      ShotCurve(timesMs: t, flow: f, weight: w ?? List.filled(t.length, 1));

  test('weights irregular intervals by time, not number of readings', () {
    final stats = CurveFlowStats.fromCurve(
      curve([0, 1000, 2000, 10000], [1, 1, 5, 5]),
      firstDripMs: 0,
    )!;
    expect(stats.mean, closeTo(4.4, 1e-10));
    expect(stats.median, closeTo(5, 1e-10));
  });

  test('clips preinfusion at the recorded drip and keeps output pauses', () {
    final stats = CurveFlowStats.fromCurve(
      curve([0, 1000, 2000, 3000, 4000, 5000], [0, 2, 0, 0, 2, 2]),
      firstDripMs: 1000,
    )!;
    expect((stats.startMs, stats.endMs), (1000, 5000));
    expect(stats.mean, closeTo(1, 1e-10));
    expect(stats.median, closeTo(1, 1e-10));
  });

  test('clips within a linear segment and uses signed flow unchanged', () {
    final stats = CurveFlowStats.fromCurve(
      curve([0, 1000, 3000], [-2, 2, 2]),
      firstDripMs: 500,
    )!;
    expect(stats.mean, closeTo(1.8, 1e-10));
    expect(stats.median, closeTo(2, 1e-10));
  });

  test(
    'estimates first drip at the 0.1 g crossing without modifying weight',
    () {
      final shot = curve([0, 2000, 5000], [0, 2, 2], w: [0, 0.2, 6]);
      final stats = CurveFlowStats.fromCurve(shot)!;
      expect(stats.startMs, 1000);
      expect(stats.mean, closeTo(1.875, 1e-10));
      expect(shot.weight, [0, 0.2, 6]);
    },
  );

  test(
    'extra pressure timestamps preserve flow statistics and scale points',
    () {
      final scale = curve([0, 1000, 2000, 10000], [1, 1, 5, 5]);
      final pressure = PressureRecording()
        ..add(200, 4.3)
        ..add(1250, 7.2)
        ..add(1260, 4.7)
        ..add(3000, 4.7);
      final combined = pressure.addTo(scale);
      final before = CurveFlowStats.fromCurve(scale, firstDripMs: 0)!;
      final after = CurveFlowStats.fromCurve(combined, firstDripMs: 0)!;
      expect(after.mean, closeTo(before.mean, 1e-10));
      expect(after.median, closeTo(before.median, 1e-10));
      expect(combined.maxOf(CurveSeries.pressure), 7.2);
      for (var i = 0; i < scale.timesMs.length; i++) {
        final position = combined.timesMs.indexOf(scale.timesMs[i]);
        expect(combined.weight[position], scale.weight[i]);
        expect(combined.flow[position], scale.flow[i]);
      }
      expect(
        ShotCurve.fromJson(combined.toJson()).maxOf(CurveSeries.pressure),
        7.2,
      );
      expect(pressure.addTo(scale), same(combined));
      pressure.add(3100, 8);
      expect(pressure.addTo(scale).maxOf(CurveSeries.pressure), 8);
    },
  );

  test('retains close peaks and highest duplicate timestamp; rejects invalid readings', () {
    final pressure = PressureRecording()
      ..add(0, 4.3)
      ..add(10, 7.2)
      ..add(10, 4.7)
      ..add(20, 4.7)
      ..add(15, 20)
      ..add(21, double.nan)
      ..add(22, double.infinity)
      ..add(23, -1);
    final combined = pressure.addTo(curve([0, 200], [0, 1]));
    expect(combined.timesMs, [0, 10, 20, 200]);
    expect(combined.pressure, [4.3, 7.2, 4.7, 4.7]);
    expect(pressure.peakBar, combined.maxOf(CurveSeries.pressure));
    pressure.clear();
    expect(pressure.peakBar, isNull);
  });

  test('includes a peak after the last scale reading and holds its weight', () {
    final recording = PressureRecording()
      ..add(0, 1)
      ..add(210, 7.2);
    final combined = recording.addTo(curve([0, 200], [0, 1], w: [0, 10]));
    expect(combined.timesMs, [0, 200, 210]);
    expect(combined.weight, [0, 10, 10]);
    expect(combined.pressure.last, 7.2);
  });

  test('missing output, zero duration, invalid time or absent flow give no statistics', () {
    for (final shot in [
      curve([0], [1]),
      curve([0, 100], [1, 1], w: [0, 0]),
      curve([100, 100], [1, 1]),
      curve([100, 50], [1, 1]),
      curve([0, 100], [double.nan, 1]),
      curve([0, 100], []),
    ]) {
      expect(CurveFlowStats.fromCurve(shot), isNull);
    }
    expect(
      CurveFlowStats.fromCurve(curve([0, 100], [1, 1]), firstDripMs: 100),
      isNull,
    );
  });
}
