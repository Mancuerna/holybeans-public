import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/domain/scale_automation.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';

import 'helpers/fake_scale.dart';

void main() {
  group('scale timer button', () {
    test('whole-second clocks use explicit state without false stops', () {
      final watch = ScaleTimerWatch();
      expect(watch.add(0, isRunning: false), isNull);
      expect(watch.add(0, isRunning: true), isTrue);
      for (final ms in [0, 0, 0, 1000, 1000, 1000, 1000]) {
        expect(watch.add(ms, isRunning: true), isNull);
      }
      expect(watch.add(1000, isRunning: false), isFalse);
      expect(watch.add(1000, isRunning: false), isNull);
      expect(watch.add(0, isRunning: true), isTrue);
    });
    test('a running timer is a press only after a stopped one', () {
      final watch = ScaleTimerWatch();
      // Already running when first seen: not a press.
      expect([0, 100, 200].map(watch.add), [null, null, null]);
      // Stops: the same time twice more.
      expect([200, 200].map(watch.add), [null, false]);
      expect(watch.add(300), isTrue);
      // Reset to zero stops it; counting again starts it.
      expect(watch.add(0), isFalse);
      expect(watch.add(100), isTrue);
    });
  });

  test('the first drop needs a tare and a gram, not a knock', () {
    final watch = FirstDripWatch();
    final found = [
      for (final (index, grams) in [
        // Moving the cup before the tare shows big weights: ignored.
        120.0, 3.0,
        // The tared cup with the machine vibrating, and a knock.
        0.0, 0.3, 0.1, 0.3, 1.5, 0.2, 0.0,
        // The drops.
        0.6, 1.1, 1.6, 2.2,
      ].indexed)
        watch.add(index * 100, grams),
    ];
    expect(found.take(12), everyElement(isNull));
    expect(found.last, 800, reason: 'the last reading at zero');
  });

  test('an espresso ends when the weight stops rising, noted back then', () {
    final watch = ShotEndWatch();
    int? endMs;
    int? clearMs;
    for (var ms = 0; ms <= 28000 && clearMs == null; ms += 100) {
      // Nothing until 7 s, then 2 g/s up to 36 g at 25 s, with a knock
      // every 400 ms once it is still.
      final grams = ms < 7000
          ? 0.0
          : ms < 25000
          ? (ms - 7000) / 500
          : 36.0 + (ms % 400 == 0 ? 0.3 : 0);
      endMs = watch.add(elapsedMs: ms, grams: grams, doseGrams: 18);
      if (endMs != null) clearMs = ms;
    }
    expect(endMs, closeTo(25000, 200));
    expect(clearMs, closeTo(26000, 200), reason: 'a still second later');

    // A stall before the dose (or 5 g without one) is not the end.
    for (final dose in [18.0, null]) {
      final stall = ShotEndWatch();
      final ends = [
        for (var ms = 6000; ms <= 9000; ms += 100)
          stall.add(elapsedMs: ms, grams: 10, doseGrams: dose),
      ];
      expect(ends.any((end) => end != null), dose == null);
    }
  });

  group('brew scale session', () {
    late FakeScale scale;
    late DateTime now;
    late BrewScaleSession session;
    var starts = 0;
    var stops = 0;
    int? stoppedAt;
    int? firstDrip;

    setUp(() async {
      scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
      now = DateTime(2026, 10, 5, 9);
      starts = 0;
      stops = 0;
      stoppedAt = null;
      firstDrip = null;
      session = BrewScaleSession(
        scale,
        clock: () => now,
        shotEnd: () => ShotEndWatch(minElapsedMs: -1, quietMs: 0),
      );
      session
        ..requestStart = (() => starts++)
        ..requestStop = ((seconds) {
          stops++;
          stoppedAt = seconds;
        })
        ..isEspresso = (() => true)
        ..doseGrams = (() => 18)
        ..onFirstDrip = ((seconds) => firstDrip = seconds);
      // Opening resets the dial; presses count once our command settled.
      expect(scale.commands, [ScaleCommand.resetTimer]);
      scale.commands.clear();
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
    });

    tearDown(() {
      session.dispose();
      scale.dispose();
    });

    test('the scale button starts and stops without echoing', () {
      for (final ms in [500, 500, 500]) {
        scale.emit(0, timerMs: ms);
      }
      scale.emit(0, timerMs: 600);
      expect(starts, 1);
      session.timerStarted(0);
      expect(scale.commands, isEmpty, reason: 'it already runs');
      for (final ms in [700, 700, 700]) {
        scale.emit(0, timerMs: ms);
      }
      expect(stops, 1);
      session.timerStopped();
      expect(scale.commands, isEmpty);
    });

    test('our own commands do not read as presses', () async {
      session.timerStarted(0);
      await Future<void>.delayed(Duration.zero);
      // A dial with time left would not tare and start in one go.
      expect(scale.commands, [
        ScaleCommand.resetTimer,
        ScaleCommand.tareAndStartTimer,
      ]);
      // The scale resets and starts its timer in reply.
      for (final ms in [900, 900, 900, 0, 100]) {
        scale.emit(0, timerMs: ms);
      }
      expect((starts, stops), (0, 0));
      now = now.add(const Duration(seconds: 3));
      for (final ms in [200, 200, 200]) {
        scale.emit(0, timerMs: ms);
      }
      expect(stops, 1, reason: 'a later press counts');
    });

    test('waiting for the drip tares, then starts with the first drop', () {
      session.waitForDrip();
      expect(session.waitingForDrip, isTrue);
      expect(scale.commands, [ScaleCommand.tare]);
      for (final grams in [150.0, 0.0, 0.3, 0.4, 1.1]) {
        scale.emit(grams);
      }
      expect(starts, 0, reason: 'vibrations, not drops');
      for (final grams in [1.5, 2.0]) {
        scale.emit(grams);
      }
      expect(starts, 1);
      expect(session.waitingForDrip, isFalse);
      session.timerStarted(0);
      expect(scale.commands.last, ScaleCommand.startTimer);
      expect(firstDrip, isNull, reason: 'the timer started with it');
    });

    test('waiting for a drop ignores the scale starting and auto-stopping on an empty cup', () async {
      session.waitForDrip();
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
      scale.emit(0, timerRunning: false);
      scale.emit(0, timerMs: 1000, timerRunning: true);
      scale.emit(0, timerMs: 2000, timerRunning: true);
      scale.emit(0, timerMs: 2000, timerRunning: false);
      scale.emit(0, timerRunning: false);
      expect((starts, stops), (0, 0));
      expect(session.waitingForDrip, isTrue);
      for (final grams in [1.2, 1.5, 2.0, 2.5]) {
        scale.emit(grams, timerRunning: false);
      }
      expect(starts, 1);
      expect(stops, 0);
      session.timerStarted(0);
      expect(scale.commands, [ScaleCommand.tare, ScaleCommand.startTimer]);
    });

    test('an espresso notes its first drip and stops when it ends', () {
      session.timerStarted(0);
      // Stale weight right after the tare is not the first drip.
      scale.emit(150);
      expect(firstDrip, isNull);
      for (final grams in [0.0, 0.4, 0.2, 1.2, 2.0]) {
        scale.emit(grams);
      }
      expect(firstDrip, isNull, reason: 'a knock is not a drop');
      scale.emit(3);
      expect(firstDrip, 1);
      scale.emit(20);
      expect(stops, 0);
      scale.emit(36);
      expect(stops, 1);
      expect(stoppedAt, 1, reason: 'when the weight stopped rising');
      session.timerStopped();
      expect(scale.commands.last, ScaleCommand.stopTimer);
    });
  });

  test('keeping the screen on is counted across screens', () async {
    final calls = <bool>[];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('holybeans/device'), (
          call,
        ) async {
          calls.add((call.arguments as Map)['on'] as bool);
          return null;
        });
    const feedback = DeviceFeedback();
    await feedback.keepScreenOn(true); // brew form
    await feedback.keepScreenOn(true); // pour assistant
    await feedback.keepScreenOn(false); // assistant closes
    expect(calls, [true]);
    await feedback.keepScreenOn(false); // form closes
    expect(calls, [true, false]);
  });
}
