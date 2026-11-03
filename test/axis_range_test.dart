import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  // A filter brew's flow: pours up to 17.6 g/s and rests near zero.
  List<double> brew() => [
    for (var i = 0; i < 400; i++)
      i % 50 < 10 ? 10 + (i % 50) * 0.76 : (i.isEven ? 0.02 : -0.03),
  ];

  test('one knock on the scale is left out on both sides', () {
    final values = brew()
      ..[397] = 98.46
      ..[398] = -37.09;
    final range = robustRange(values);
    expect(range.high, closeTo(16.84, 0.01));
    expect(range.low, -0.03);
  });

  test('a brew without spikes keeps its extremes', () {
    final range = robustRange(brew());
    expect(range.high, closeTo(16.84, 0.01));
    expect(range.low, -0.03);
  });

  test('many high readings are real and kept', () {
    final values = brew();
    for (var i = 0; i < 12; i++) {
      values[i * 30] = 60;
    }
    expect(robustRange(values).high, 60);
  });

  test('short series and empty ones keep every value', () {
    expect(robustRange(const []), (low: 0.0, high: 0.0));
    expect(robustRange(const [1, 2, 90]), (low: 1.0, high: 90.0));
  });

  test("a curve's peak leaves out the knock but its maximum keeps it", () {
    final flow = brew()..[397] = 98.46;
    final curve = ShotCurve(
      timesMs: [for (var i = 0; i < flow.length; i++) i * 200],
      flow: flow,
      weight: [for (var i = 0; i < flow.length; i++) i / 2],
    );
    expect(curve.maxOf(CurveSeries.flow), 98.46);
    expect(curve.peakOf(CurveSeries.flow), closeTo(16.84, 0.01));
    expect(curve.peakOf(CurveSeries.weight), 199.5);
  });
}
