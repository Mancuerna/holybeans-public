import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  test(
    'optimized curves retain Gaussian samples and time-weighted medians',
    () {
      final random = math.Random(71);
      for (var trial = 0; trial < 300; trial++) {
        final count = 3 + random.nextInt(100);
        final times = <int>[0];
        for (var i = 1; i < count; i++) {
          times.add(
            times.last + (trial.isEven ? 100 : 1 + random.nextInt(300)),
          );
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
        for (final series in shot.series) {
          final source = shot.values(series);
          for (var i = 0; i < count; i++) {
            var sum = 0.0;
            var total = 0.0;
            for (var j = 0; j < count; j++) {
              final distance = times[j] - times[i];
              if (distance.abs() > 1200) continue;
              final factor = math.exp(-distance * distance / (2.0 * 400 * 400));
              sum += source[j] * factor;
              total += factor;
            }
            expect(smooth.values(series)[i], sum / total);
          }
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
    },
  );
}
