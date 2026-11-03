import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';

import 'helpers/fake_pressure_sensor.dart';

void main() {
  test(
    'trace preserves snapshots, replaces duplicates and rejects invalid points',
    () {
      final trace = PressureTrace()
        ..add(0, 2)
        ..add(100, 3);
      final snapshot = trace.points;
      trace
        ..add(100, 4)
        ..add(99, 8)
        ..add(120, double.nan)
        ..add(150, 31)
        ..add(180, -1)
        ..add(200, 5);
      expect(snapshot.map((p) => p.bar), [2, 3]);
      expect(trace.points.map((p) => p.bar), [2, 4, 5]);
      expect(trace.points.last.breakBefore, isTrue);
      expect(() => trace.points.clear(), throwsUnsupportedError);
    },
  );
  test('pauses and missing readings leave gaps, clear starts a new shot', () {
    final trace = PressureTrace()
      ..add(0, 2)
      ..add(100, 3)
      ..add(2100, 5)
      ..add(2200, 6)
      ..breakSegment()
      ..add(2300, 7);
    expect(trace.points.map((p) => p.breakBefore), [
      true,
      false,
      true,
      false,
      true,
    ]);
    trace
      ..clear()
      ..add(0, 1);
    expect(trace.points.single, (elapsedMs: 0, bar: 1.0, breakBefore: true));
  });
  test(
    'session records only while running and preserves measured curve semantics',
    () async {
      final sensor = FakePressureSensor(name: 'BOOKOO', connected: true);
      final clock = _Clock();
      final session = BrewPressureSession(sensor, stopwatch: clock);
      sensor.emit(2);
      expect(session.trace.points, isEmpty);
      session.timerStarted(0);
      sensor.emit(2);
      clock.elapsed = const Duration(milliseconds: 100);
      sensor.emit(4);
      session.timerStopped();
      sensor.emit(9);
      expect(session.trace.points.map((p) => p.bar), [2, 4]);
      session.timerStarted(1);
      clock.elapsed = const Duration(milliseconds: 200);
      sensor.emit(5);
      expect(session.trace.points.last.elapsedMs, 1100);
      expect(session.trace.points.last.breakBefore, isTrue);
      await sensor.disconnect();
      clock.elapsed = const Duration(milliseconds: 300);
      await sensor.connect();
      sensor.emit(6);
      expect(session.trace.points.last.breakBefore, isTrue);
      expect(session.peakBar, 6);
      final saved = session.withPressure(
        ShotCurve(timesMs: [0, 300], weight: [0, 3], flow: []),
      );
      expect(saved.pressure, [2, 4, 5, 6]);
      expect(saved.timesMs, [0, 100, 200, 300]);
      session.timerReset();
      expect(session.trace.points, isEmpty);
      session.timerStarted(0);
      sensor.emit(1);
      expect(session.trace.points.single.elapsedMs, 0);
      session.dispose();
      sensor.dispose();
    },
  );
}

class _Clock implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
  @override
  bool isRunning = false;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
  @override
  void reset() => elapsed = Duration.zero;
  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get frequency => 1000000;
}
