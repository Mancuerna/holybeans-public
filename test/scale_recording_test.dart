import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  test('a recording keeps a reading every so often, in order', () {
    final recording = WeightRecording();
    expect(recording.curve, isNull);
    recording
      ..add(0, const ScaleReading(grams: 0))
      ..add(40, const ScaleReading(grams: 1))
      ..add(100, const ScaleReading(grams: 3, flowGramsPerSecond: 2.5))
      ..add(90, const ScaleReading(grams: 2))
      ..add(250, const ScaleReading(grams: 6.4, flowGramsPerSecond: 4));
    final curve = recording.curve!;
    expect(curve.timesMs, [0, 100, 250]);
    expect(curve.weight, [0, 3, 6.4]);
    expect(curve.flow, [0, 2.5, 4]);
    expect(curve.series, [CurveSeries.weight, CurveSeries.flow]);
    expect(recording.lastGrams, 6.4);

    recording.clear();
    expect(recording.isEmpty, isTrue);
    expect(recording.lastGrams, isNull);
  });

  test('after a tare, the old weight is not recorded', () {
    final recording = WeightRecording()..restartAfterTare();
    recording
      ..add(0, const ScaleReading(grams: 352.4))
      ..add(150, const ScaleReading(grams: 0.1))
      ..add(300, const ScaleReading(grams: 30))
      ..add(400, const ScaleReading(grams: 29.2));
    expect(recording.curve!.weight, [0.1, 30, 29.2]);
    expect(recording.peakGrams, 30);
    expect(recording.lastGrams, 29.2);

    // A scale that ignores the tare is recorded after a while anyway.
    final stubborn = WeightRecording()..restartAfterTare();
    stubborn
      ..add(0, const ScaleReading(grams: 352))
      ..add(1600, const ScaleReading(grams: 360));
    expect(stubborn.curve, isNull);
    expect(stubborn.lastGrams, 360);
  });

  test('a curve without pressure survives being saved', () {
    final curve = ShotCurve(
      timesMs: const [0, 500, 1000],
      flow: const [0, 3.2, 4.1],
      weight: const [0, 1.6, 3.65],
    );
    final json = curve.toJson();
    expect(json, isNot(contains('"p"')));
    final read = ShotCurve.fromJson(json);
    expect(read.pressure, isEmpty);
    expect(read.weight, [0, 1.6, 3.65]);
    expect(read.series, [CurveSeries.weight, CurveSeries.flow]);
    expect(read.smoothed().pressure, isEmpty);
    expect(read.maxOf(CurveSeries.pressure), 0);
  });
}
