import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';

void main() {
  late FakeScale scale;
  late ManualStopwatch watch;
  late BrewScaleSession session;
  late DateTime now;
  var starts = 0;
  int? firstDrip;

  setUp(() async {
    scale = FakeScale(name: 'BOOKOO_SC', connected: true);
    watch = ManualStopwatch();
    now = DateTime(2026);
    starts = 0;
    firstDrip = null;
    session = BrewScaleSession(scale, stopwatch: watch, clock: () => now)
      ..isEspresso = (() => true)
      ..doseGrams = (() => 17)
      ..onFirstDrip = ((seconds) => firstDrip = seconds);
    session
      ..requestStart = (() {
        starts++;
        session.timerStarted(
          session.restartsOnNextStart ? 0 : watch.elapsedMilliseconds ~/ 1000,
        );
      })
      ..requestStop = ((_) => session.timerStopped());
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 3));
    for (var i = 0; i < 3; i++) {
      scale.emit(0);
    }
    scale.commands.clear();
  });

  tearDown(() {
    session.dispose();
    scale.dispose();
  });

  void emit(int ms, double grams) {
    watch.elapsed = Duration(milliseconds: ms);
    scale.emit(grams, timerMs: ms + 100);
  }

  Future<void> start(bool physical) async {
    if (physical) {
      scale.emit(129.9, timerMs: 100);
      expect(starts, 1);
    } else {
      session.timerStarted(0);
    }
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 3));
    expect(session.recording, isTrue);
  }

  for (final physical in [false, true]) {
    for (final espresso in [false, true]) {
      test(
        'fresh start waits for zero: physical=$physical, espresso=$espresso',
        () async {
          session.isEspresso = () => espresso;
          session.pourFinished(
            ShotCurve(timesMs: [0, 100], flow: [0, 0], weight: [0, 200]),
          );
          await start(physical);
          expect(session.curve, isNull);
          expect(session.beverageGrams, isNull);
          expect(
            scale.commands,
            physical
                ? <ScaleCommand>[]
                : [ScaleCommand.resetTimer, ScaleCommand.tareAndStartTimer],
          );

          // Holding the button longer than the former 1.5 s tare timeout must
          // not seed the guard, the peak weight or first-drip detection.
          for (final ms in [100, 300, 1500, 2000, 3000]) {
            emit(ms, 129.9);
            expect(session.curve, isNull);
            expect(session.beverageGrams, isNull);
            expect(session.flowTrace.points, isEmpty);
            expect(firstDrip, isNull);
          }
          emit(3100, 0);
          expect(session.beverageGrams, 0);
          for (final (ms, grams) in [
            (4000, 2.0),
            (5000, 4.0),
            (6000, 6.0),
            (10000, 15.0),
            (15000, 28.0),
            (20000, 40.0),
            (24000, 46.6),
          ]) {
            emit(ms, grams);
          }
          session.timerStopped();
          expect(session.curve!.timesMs.first, 3100);
          expect(session.curve!.weight.first, 0);
          expect(session.curve!.weight.last, 46.6);
          expect(session.beverageGrams, 46.6);
          expect((session.beverageGrams! / 17).toStringAsFixed(1), '2.7');
          if (espresso) expect(firstDrip, 3);
        },
      );
    }

    test(
      'resume preserves weight without waiting for zero: physical=$physical',
      () async {
        await start(physical);
        emit(100, 0);
        emit(1000, 12);
        emit(2000, 20);
        // A physical pause leaves the scale clock unchanged across readings.
        scale.emit(20, timerMs: 2100);
        scale.emit(20, timerMs: 2100);
        expect(session.recording, isFalse);
        final before = session.curve!.weight.toList();
        scale.commands.clear();
        if (physical) {
          scale.emit(20, timerMs: 2200);
        } else {
          session.timerStarted(2);
        }
        expect(session.recording, isTrue);
        expect(
          scale.commands,
          physical ? <ScaleCommand>[] : [ScaleCommand.startTimer],
        );
        emit(2300, 22);
        expect(session.curve!.weight, [...before, 22]);
        expect(session.beverageGrams, 22);
      },
    );
  }

  test(
    'physical reset starts a clean recording and waits for zero again',
    () async {
      await start(true);
      emit(100, 0);
      emit(1000, 12);
      emit(6000, 46.6);
      session.timerStopped();
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
      scale.emit(0);
      expect(session.restartsOnNextStart, isTrue);
      scale.emit(129.9, timerMs: 100);
      expect(starts, 2);
      expect(session.recording, isTrue);
      expect(session.curve, isNull);
      expect(session.beverageGrams, isNull);
      expect(session.flowTrace.points, isEmpty);
      emit(2000, 129.9);
      expect(session.beverageGrams, isNull);
      emit(3000, 0);
      emit(4000, 5);
      expect(session.curve!.weight, [0, 5]);
      expect(session.beverageGrams, 5);
    },
  );

  test('zero on the physical start notification confirms tare', () {
    scale.emit(0, timerMs: 100);
    expect(session.recording, isTrue);
    emit(100, 2);
    emit(200, 3);
    expect(session.curve!.weight, [0, 2, 3]);
    expect(session.beverageGrams, 3);
  });
}
