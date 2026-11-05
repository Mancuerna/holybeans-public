import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/curve_sampling.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  test('flow display is invariant under interpolation and retains time-weighted medians', () {
    final random = math.Random(71);
    for (var trial = 0; trial < 300; trial++) {
      final count = 3 + random.nextInt(100);
      final times = <int>[0];
      for (var i = 1; i < count; i++) {
        times.add(times.last + (trial.isEven ? 100 : 1 + random.nextInt(300)));
      }
      final flow = [
        for (var i = 0; i < count; i++) (random.nextInt(12) - 3).toDouble(),
      ];
      final shot = ShotCurve(
        timesMs: times,
        flow: flow,
        weight: List.filled(count, 1),
        pressure: trial % 3 == 0 ? flow : const [],
      );
      final smooth = shot.smoothed();
      expect(smooth.timesMs, same(times));
      expect(smooth.pressure, same(shot.pressure));
      expect(smooth.weight, same(shot.weight));
      final denseTimes = <int>{
        ...times,
        for (var i = 1; i < count; i++) (times[i - 1] + times[i]) ~/ 2,
      }.toList()..sort();
      final dense = ShotCurve(
        timesMs: denseTimes,
        flow: resampleCurveSeries(times, flow, denseTimes),
        weight: const [],
      ).smoothed();
      for (var i = 0; i < count; i++) {
        expect(
          smooth.flow[i],
          closeTo(dense.flow[dense.indexAt(times[i])], 1e-10),
        );
        expect(
          smooth.flow[i],
          inInclusiveRange(
            flow.reduce(math.min) - 1e-10,
            flow.reduce(math.max) + 1e-10,
          ),
        );
      }
      double quantile(bool upper) {
        var low = flow.reduce(math.min);
        var high = flow.reduce(math.max);
        for (var n = 0; n < 48; n++) {
          final value = (low + high) / 2;
          var below = 0.0;
          for (var i = 1; i < count; i++) {
            final a = math.min(flow[i - 1], flow[i]);
            final b = math.max(flow[i - 1], flow[i]);
            final fraction = a == b
                ? (value >= a ? 1.0 : 0.0)
                : ((value - a) / (b - a)).clamp(0.0, 1.0);
            below += fraction * (times[i] - times[i - 1]);
          }
          if (upper ? below <= times.last / 2 : below < times.last / 2) {
            low = value;
          } else {
            high = value;
          }
        }
        return (low + high) / 2;
      }

      final stats = CurveFlowStats.fromCurve(shot, firstDripMs: 0)!;
      expect(
        stats.median,
        closeTo((quantile(false) + quantile(true)) / 2, 1e-10),
      );
      expect(shot.flow, same(flow));
    }
  });
}
