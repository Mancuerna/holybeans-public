import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';

void main() {
  test(
    'live flow follows accepted weights, expires, and retains a stopped trace',
    () async {
      final scale = FakeScale(name: 'BOOKOO', connected: true);
      final watch = ManualStopwatch();
      var now = DateTime(2026);
      final session = BrewScaleSession(
        scale,
        stopwatch: watch,
        clock: () => now,
      );
      session.isEspresso = () => true;
      scale.emit(40);
      expect(session.flowTrace.points, isEmpty);
      session.timerStarted(0);
      void emit(int ms, double grams) {
        watch.elapsed = Duration(milliseconds: ms);
        scale.emit(grams, flow: 99, timerMs: ms, timerRunning: true);
      }

      emit(
        100,
        40,
      ); // The old cup load before tare must not become a flow spike.
      expect(session.flowGramsPerSecond, isNull);
      expect(session.guideWeightGrams, isNull);
      emit(200, 0);
      expect(session.guideWeightGrams, 0);
      emit(700, 1);
      emit(1200, 2);
      expect(session.flowGramsPerSecond, 2);
      expect(session.guideWeightGrams, 2);
      now = now.add(const Duration(seconds: 2));
      expect(session.flowGramsPerSecond, isNull);
      expect(session.guideWeightGrams, isNull);
      emit(1300, 2.2);
      expect(session.flowGramsPerSecond, closeTo(2, 0.001));
      final recorded = session.curve!.toJson();
      final trace = session.flowTrace.points;
      session.timerStopped();
      expect(session.guideWeightGrams, 2.2);
      scale.emit(-40);
      expect(session.guideWeightGrams, 2.2);
      expect(session.flowGramsPerSecond, isNull);
      expect(session.flowTrace.points, same(trace));
      expect(session.curve!.toJson(), recorded);
      session.timerStarted(2);
      emit(1400, 2.4);
      expect(session.flowGramsPerSecond, isNull);
      emit(1900, 3.4);
      expect(session.flowTrace.points.last.elapsedMs, 2600);
      expect(session.flowTrace.points.last.breakBefore, isTrue);
      await scale.disconnect();
      expect(session.flowGramsPerSecond, isNull);
      expect(session.guideWeightGrams, isNull);
      session.timerReset();
      expect(session.guideWeightGrams, isNull);
      expect(session.flowTrace.points, isEmpty);
      expect(session.curve, isNull);
      session.dispose();
      scale.dispose();
    },
  );
}
