import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/curve_accumulator.dart';
import 'package:holybeans/domain/prepared_curve.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/curve_worker.dart';

void equivalent(PreparedCurve actual, PreparedCurve expected) {
  for (final series in expected.recorded.series) {
    expect(
      actual.shown.values(series),
      orderedEquals(expected.shown.values(series)),
    );
    expect(actual.peaks[series], expected.peaks[series]);
  }
  final a = actual.flowStats;
  final b = expected.flowStats;
  if (b == null) {
    expect(a, isNull);
    return;
  }
  expect(a, isNotNull);
  expect(a!.startMs, b.startMs);
  expect(a.endMs, b.endMs);
  expect(a.mean, closeTo(b.mean, 1e-9));
  expect(a.median, closeTo(b.median, 1e-8));
  expect(a.max, closeTo(b.max!, 1e-9));
}

void main() {
  for (final irregular in [false, true]) {
    test(
      'incremental curve matches complete calculation, irregular=$irregular',
      () {
        final engine = CurveAccumulator();
        final random = Random(71);
        final times = <int>[];
        final flow = <double>[];
        final pressure = <double>[];
        final weight = <double>[];
        for (var i = 0; i < 600; i++) {
          times.add(
            i == 0
                ? 0
                : times.last + (irregular ? 30 + random.nextInt(150) : 100),
          );
          flow.add(i % 35 < 5 ? 0 : random.nextDouble() * 6 - 1);
          pressure.add(random.nextDouble() * 9);
          weight.add(i < 8 ? 0 : (i - 8) * .17);
          if (i % 17 != 0 && i != 599) continue;
          final curve = ShotCurve(
            timesMs: [...times],
            flow: [...flow],
            pressure: [...pressure],
            weight: [...weight],
          );
          equivalent(
            engine.prepare((curve: curve, firstDripMs: null)),
            prepareCurve((curve: curve, firstDripMs: null)),
          );
        }
        expect(engine.integratedSegments, lessThan(600));
        expect(engine.smoothedSamples, lessThan(600 * 5));
        flow[20] = 14;
        final changed = ShotCurve(
          timesMs: times,
          flow: flow,
          pressure: pressure,
          weight: weight,
        );
        equivalent(
          engine.prepare((curve: changed, firstDripMs: 2097)),
          prepareCurve((curve: changed, firstDripMs: 2097)),
        );
        final shortened = ShotCurve(
          timesMs: times.take(300).toList(),
          flow: flow.take(300).toList(),
          weight: weight.take(300).toList(),
        );
        equivalent(
          engine.prepare((curve: shortened, firstDripMs: null)),
          prepareCurve((curve: shortened, firstDripMs: null)),
        );
      },
    );
  }
  test(
    'append after a gap revisits the old endpoint and preserves raw series',
    () {
      final engine = CurveAccumulator();
      final times = [0, 50, 100, 150, 200, 500, 510, 550];
      final values = <double>[0, 1, 8, 0, 2, 0, 3, 1];
      for (var n = 3; n <= times.length; n++) {
        final shot = ShotCurve(
          timesMs: times.take(n).toList(),
          pressure: values.take(n).toList(),
          flow: values.take(n).toList(),
          weight: values.take(n).toList(),
        );
        final request = (curve: shot, firstDripMs: 0);
        final result = engine.prepare(request);
        equivalent(result, prepareCurve(request));
        expect(result.shown.pressure, shot.pressure);
        expect(result.shown.weight, shot.weight);
        expect(result.shown.flow.last, shot.flow.last);
      }
    },
  );

  test('plateaus, signed flow, missing weight and a future first drip', () {
    for (final flow in <List<double>>[
      [-2.0, -2, 2, 2],
      [0.0, 0, 0, 0],
      [1.0, 4, 4, 1],
    ]) {
      for (final first in <int?>[null, 0, 101, 1000]) {
        final engine = CurveAccumulator();
        for (var n = 2; n <= 4; n++) {
          final request = (
            curve: ShotCurve(
              timesMs: [0, 100, 200, 300].take(n).toList(),
              flow: flow.take(n).toList(),
              weight: const [],
            ),
            firstDripMs: first,
          );
          equivalent(engine.prepare(request), prepareCurve(request));
        }
      }
    }
  });
  test('nearly flat segments preserve median between separated plateaus', () {
    final curve = ShotCurve(
      timesMs: [for (var i = 0; i < 1000; i++) i * 100],
      flow: [
        for (var i = 0; i < 1000; i++) (i < 500 ? 1.0 : 10.0) + (i % 3) * 1e-12,
      ],
      weight: const [],
    );
    final request = (curve: curve, firstDripMs: 0);
    equivalent(CurveAccumulator().prepare(request), prepareCurve(request));
  });

  test('persistent worker returns coherent snapshots and closes', () async {
    final worker = CurveWorker();
    addTearDown(worker.dispose);
    for (final n in [300, 400, 100]) {
      final request = (
        curve: ShotCurve(
          timesMs: [for (var i = 0; i < n; i++) i * 100],
          flow: [for (var i = 0; i < n; i++) sin(i / 30)],
          weight: [for (var i = 0; i < n; i++) i / 10],
        ),
        firstDripMs: 10,
      );
      equivalent(await worker.prepare(request), prepareCurve(request));
    }
  });
}
