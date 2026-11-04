import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/prepared_curve.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/curve_view_model.dart';

ShotCurve curve(int count) => ShotCurve(
  timesMs: [for (var i = 0; i < count; i++) i * 100 + i % 3],
  pressure: [for (var i = 0; i < count; i++) i == 4251 ? 12 : 9],
  flow: [for (var i = 0; i < count; i++) i == 8182 ? -2 : 1 + math.sin(i / 10)],
  weight: [for (var i = 0; i < count; i++) i == 7001 ? 100 : i * 0.001],
);

void main() {
  test('display is bounded and retains endpoints and narrow extrema of every series', () {
    final original = curve(10000);
    final before = original.toJson();
    final display = displayCurve(original);
    expect(display.timesMs.length, lessThanOrEqualTo(1024));
    expect(display.timesMs.first, original.timesMs.first);
    expect(display.timesMs.last, original.timesMs.last);
    expect(display.pressure, contains(12));
    expect(display.flow, contains(-2));
    expect(display.weight, contains(100));
    for (var i = 0; i < display.timesMs.length; i++) {
      final index = original.timesMs.indexOf(display.timesMs[i]);
      expect(index, greaterThanOrEqualTo(0));
      for (final series in original.series) {
        expect(display.values(series)[i], original.values(series)[index]);
      }
      if (i > 0) {
        expect(display.timesMs[i], greaterThan(display.timesMs[i - 1]));
      }
    }
    expect(original.toJson(), before);
    expect(displayCurve(curve(100)).timesMs, hasLength(100));
  });

  test('preparation retains full cursor samples and statistics', () {
    final original = curve(1500);
    final prepared = prepareCurve((curve: original, firstDripMs: 10));
    final statistics = CurveFlowStats.fromCurve(original, firstDripMs: 10)!;
    expect(prepared.recorded, same(original));
    expect(prepared.shown.timesMs, original.timesMs);
    expect(prepared.shown.flow, original.smoothed().flow);
    expect(prepared.flowStats!.mean, statistics.mean);
    expect(prepared.flowStats!.median, statistics.median);
    for (final series in original.series) {
      expect(
        prepared.peaks[series],
        series == CurveSeries.pressure
            ? original.maxOf(series)
            : original.peakOf(series),
      );
    }
  });

  test('live preparation shows completed coherent snapshots and coalesces pending input', () async {
    final pending = <Completer<PreparedCurve>>[];
    final inputs = <CurveRequest>[];
    final model = CurveViewModel(
      prepare: (request) {
        inputs.add(request);
        final result = Completer<PreparedCurve>();
        pending.add(result);
        return result.future;
      },
    );
    addTearDown(model.dispose);
    final first = curve(300);
    final latest = curve(302);
    model.update(first, live: true);
    model.update(curve(301), live: true);
    model.update(latest, live: true);
    expect(inputs, hasLength(1));
    pending.first.complete(prepareCurve(inputs.first));
    await pumpEventQueue();
    expect(model.value!.recorded, same(first));
    expect(inputs, hasLength(2));
    expect(inputs.last.curve, same(latest));
    pending.last.complete(prepareCurve(inputs.last));
    await pumpEventQueue();
    expect(model.value!.recorded, same(latest));
  });

  test('static replacements discard obsolete curves and small curves supersede workers', () async {
    final pending = <Completer<PreparedCurve>>[];
    final inputs = <CurveRequest>[];
    final model = CurveViewModel(
      prepare: (request) {
        inputs.add(request);
        final result = Completer<PreparedCurve>();
        pending.add(result);
        return result.future;
      },
    );
    addTearDown(model.dispose);
    model.update(curve(600));
    model.update(curve(601));
    pending.first.complete(prepareCurve(inputs.first));
    await pumpEventQueue();
    expect(model.value, isNull);
    final small = curve(20);
    model.update(small);
    expect(model.value!.recorded, same(small));
    pending.last.complete(prepareCurve(inputs.last));
    await pumpEventQueue();
    expect(model.value!.recorded, same(small));
  });

  test(
    'obsolete failures are ignored and a current failure ends loading',
    () async {
      final pending = <Completer<PreparedCurve>>[];
      final model = CurveViewModel(
        prepare: (_) {
          final result = Completer<PreparedCurve>();
          pending.add(result);
          return result.future;
        },
      );
      addTearDown(model.dispose);
      model.update(curve(600));
      model.update(curve(601));
      pending.first.completeError(StateError('obsolete'));
      await pumpEventQueue();
      expect(model.error, isNull);
      pending.last.completeError(StateError('current'));
      await pumpEventQueue();
      expect(model.error, isStateError);
      expect(model.value, isNull);
    },
  );

  test('disposing drops queued preparation and ignores completion', () async {
    final pending = Completer<PreparedCurve>();
    final model = CurveViewModel(prepare: (_) => pending.future);
    final original = curve(600);
    model.update(original);
    model.update(curve(601));
    model.dispose();
    pending.complete(prepareCurve((curve: original, firstDripMs: null)));
    await pumpEventQueue();
    expect(model.value, isNull);
  });
}
