import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  ShotCurve curve(List<int> times, List<double> weights) => ShotCurve(
    timesMs: times,
    weight: weights,
    flow: List.filled(times.length, 99),
  );

  test(
    'uses cup weight, not device flow, on the original extraction clock',
    () {
      final source = curve([0, 500, 1000, 1500, 2000], [0, 1, 2, 3, 4]);
      final original = source.toJson();
      final guide = FlowGuide.fromCurve(source)!;
      expect(guide.targetAt(499), isNull);
      expect(guide.targetAt(500), 2);
      expect(guide.targetAt(1250), 2);
      expect(guide.targetAt(2000), 2);
      expect(guide.targetAt(2001), isNull);
      expect(source.toJson(), original);
      source.weight[2] = 80;
      expect(guide.targetAt(1250), 2);
      expect(guide.points.clear, throwsUnsupportedError);
    },
  );

  test('irregular sampling and zero-flow preinfusion retain their timing', () {
    final guide = FlowGuide.fromCurve(
      curve([0, 500, 1000, 1400, 1900, 2400], [0, 0, 0, 0.8, 1.8, 2.8]),
    )!;
    expect(guide.targetAt(750), 0);
    expect(guide.targetAt(2400), closeTo(2, 0.0001));
    expect(guide.endMs, 2400);
  });

  test('missing samples are gaps, not interpolated reference targets', () {
    final guide = FlowGuide.fromCurve(
      curve([0, 500, 1000, 3500, 4000, 4500], [0, 1, 2, 7, 8, 9]),
    )!;
    expect(guide.targetAt(1000), 2);
    expect(guide.targetAt(2000), isNull);
    expect(guide.targetAt(3999), isNull);
    expect(guide.targetAt(4000), 2);
    expect(guide.points[2].breakBefore, isTrue);
  });

  test('rejects absent weight, flat, unordered and unusable references', () {
    for (final source in [
      curve([], []),
      curve([0, 500], [0, 1]),
      curve([0, 500, 1000], []),
      curve([0, 500, 1000], [0, 0, 0]),
      curve([0, 0, 1000], [0, 1, 2]),
      curve([0, 1000, 500], [0, 1, 2]),
      curve([-1, 500, 1000], [0, 1, 2]),
      curve([0, 500, 1000], [0, double.nan, 2]),
    ]) {
      expect(FlowGuide.fromCurve(source), isNull);
    }
  });

  test('smooths weight jitter without depending on a device flow reading', () {
    final trace = FlowTrace();
    for (var ms = 0; ms <= 3000; ms += 100) {
      trace.add(ms, 2 * ms / 1000 + (ms % 200 == 0 ? 0.02 : -0.02));
      if (ms >= 1000) expect(trace.current, closeTo(2, 0.1));
    }
    final snapshot = trace.points;
    trace.add(3100, 6.2);
    expect(snapshot.last.elapsedMs, 3000);
    expect(snapshot.clear, throwsUnsupportedError);
  });

  test('tare, cup removal, invalid load and pauses require a fresh window', () {
    for (final load in [0.0, -50.0, 80.0, double.nan, double.infinity]) {
      final trace = FlowTrace()
        ..add(0, 0)
        ..add(500, 1)
        ..add(1000, 2);
      expect(trace.current, 2);
      trace.add(1100, load);
      expect(trace.current, isNull);
      trace.breakSegment();
      trace.add(1200, 0);
      trace.add(1700, 1);
      expect(trace.current, 2);
      expect(trace.points.last.breakBefore, isTrue);
      trace.clear();
      expect(trace.points, isEmpty);
      expect(trace.current, isNull);
    }
  });
}
