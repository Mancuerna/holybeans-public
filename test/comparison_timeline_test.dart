import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  ComparisonCurve curve({String unit = 'g/s', int end = 4000}) =>
      ComparisonCurve(
        ShotCurve(
          timesMs: [0, 1000, end],
          weight: [0, 2, 8],
          flow: [0, 2, 4],
          pressure: [0, 9, 6],
        ),
        unit,
      );
  test('cursor interpolates recorded values and never holds endpoints outside a shot', () {
    final timeline = ComparisonTimeline(a: curve(), b: curve(end: 6000));
    expect(timeline.at(CurveSeries.flow, 500, second: false), 1);
    expect(timeline.at(CurveSeries.flow, 4000, second: false), 4);
    expect(timeline.at(CurveSeries.flow, 4001, second: false), isNull);
    expect(timeline.at(CurveSeries.flow, -1, second: false), isNull);
    expect(timeline.at(CurveSeries.flow, double.nan, second: false), isNull);
    expect(timeline.difference(CurveSeries.flow, 5000), isNull);
    expect(
      timeline.at(CurveSeries.flow, 5000, second: true),
      closeTo(3.6, 1e-9),
    );
    expect(timeline.maxMs, 6000);
  });
  test('first drip shifts both timelines, retains preinfusion and does not stretch time', () {
    final timeline = ComparisonTimeline(
      a: curve(),
      b: curve(end: 6000),
      firstDripA: 1000,
      firstDripB: 2000,
      alignment: ComparisonAlignment.firstDrip,
    );
    expect(timeline.canAlignDrip, isTrue);
    expect(timeline.minMs, -2000);
    expect(timeline.maxMs, 4000);
    expect(timeline.at(CurveSeries.weight, 0, second: false), 2);
    expect(
      timeline.at(CurveSeries.weight, 0, second: true),
      closeTo(3.2, 1e-9),
    );
    expect(timeline.at(CurveSeries.pressure, 3500, second: false), isNull);
    expect(timeline.peak(CurveSeries.pressure, second: false), 9);
  });
  test(
    'missing, negative or out of curve first drip cannot enable alignment',
    () {
      for (final drip in [null, -1, 6001]) {
        final timeline = ComparisonTimeline(
          a: curve(),
          b: curve(),
          firstDripA: 1000,
          firstDripB: drip,
          alignment: ComparisonAlignment.firstDrip,
        );
        expect(timeline.canAlignDrip, isFalse);
        expect(timeline.alignment, ComparisonAlignment.start);
        expect(timeline.minMs, 0);
      }
      final timeline = ComparisonTimeline(
        a: null,
        b: curve(),
        firstDripA: 1000,
        firstDripB: 1000,
      );
      expect(timeline.canAlignDrip, isFalse);
    },
  );
  test(
    'mixed flow units do not produce a delta, while pressure and weight can',
    () {
      final timeline = ComparisonTimeline(
        a: curve(),
        b: curve(unit: 'ml/s'),
      );
      expect(timeline.difference(CurveSeries.flow, 1000), isNull);
      expect(timeline.difference(CurveSeries.pressure, 1000), 0);
      expect(timeline.difference(CurveSeries.weight, 1000), 0);
    },
  );
  test('unordered and repeated timestamps preserve the raw peak without changing stored arrays', () {
    final raw = ShotCurve(
      flow: [],
      timesMs: [2000, -1, 0, 1000, 1000],
      weight: [4, 0, 0, 1, 2],
      pressure: [6, 100, double.nan, 12, 8],
    );
    final timeline = ComparisonTimeline(
      a: ComparisonCurve(raw, 'g/s'),
      b: null,
    );
    expect(timeline.peak(CurveSeries.pressure, second: false), 12);
    expect(timeline.at(CurveSeries.pressure, 1000, second: false), 8);
    expect(timeline.at(CurveSeries.pressure, 1500, second: false), 7);
    expect(raw.timesMs, [2000, -1, 0, 1000, 1000]);
    expect(timeline.maxMs, 2000);
  });
  test('missing series and empty curves have no values', () {
    final timeline = ComparisonTimeline(
      a: ComparisonCurve(
        ShotCurve(timesMs: [0, 1000], flow: [], weight: [0, 1]),
        'g/s',
      ),
      b: null,
    );
    expect(timeline.at(CurveSeries.flow, 1000, second: false), isNull);
    expect(timeline.peak(CurveSeries.pressure, second: false), isNull);
    expect(timeline.difference(CurveSeries.weight, 1000), isNull);
    expect(ComparisonTimeline(a: null, b: null).maxMs, 1000);
  });
}
