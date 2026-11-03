import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

import 'helpers/fake_scale.dart';

class RejectingScale extends FakeScale {
  RejectingScale() : super(name: 'BOOKOO_SC_U', connected: true);
  bool reject = false;
  @override
  Future<bool> send(ScaleCommand command) async {
    if (reject) return false;
    return super.send(command);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RejectingScale scale;
  late BrewScaleSession session;
  late BrewTimer timer;
  late DateTime now;
  late TextEditingController minutes;
  late TextEditingController seconds;
  setUp(() async {
    scale = RejectingScale();
    now = DateTime(2026, 10, 17);
    session = BrewScaleSession(scale, clock: () => now);
    minutes = TextEditingController();
    seconds = TextEditingController();
    timer = BrewTimer(
      minutes: minutes,
      seconds: seconds,
      onStart: session.timerStarted,
      onStop: session.timerStopped,
      onReset: session.timerReset,
    );
    timer.allowStart = () => scale.connected;
    timer.restartOnStart = () => session.restartsOnNextStart;
    session.requestStart = () {
      if (!timer.running) timer.toggle();
    };
    session.requestStop = (at) {
      timer.stop();
      if (at != null) timer.settle(at);
    };
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 3));
    for (var i = 0; i < 3; i++) {
      scale.emit(0);
    }
  });
  tearDown(() {
    timer.dispose();
    session.dispose();
    scale.dispose();
    minutes.dispose();
    seconds.dispose();
  });
  Future<void> start() async {
    timer.toggle();
    await Future<void>.delayed(Duration.zero);
    scale.emit(0, timerMs: 100);
  }

  Future<void> samples() async {
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 110));
      scale.emit(i * 5.0, timerMs: i * 100 + 100);
    }
  }

  for (final alreadyStopped in [true, false]) {
    test('espresso zero retains result, stopped=$alreadyStopped', () async {
      session.isEspresso = () => true;
      await start();
      await samples();
      if (!alreadyStopped) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      now = now.add(const Duration(seconds: 3));
      scale.emit(31.2, timerMs: 8700);
      seconds.text = '08';
      if (alreadyStopped) timer.stop();
      await Future<void>.delayed(Duration.zero);
      final previous = session.curve;
      scale.emit(0);
      now = now.add(const Duration(seconds: 3));
      scale.emit(0);
      expect(timer.running, isFalse);
      expect(timer.elapsedSeconds, 8);
      expect(session.curve, isNotNull);
      expect(session.beverageGrams, greaterThan(0));
      expect(session.restartsOnNextStart, isTrue);
      if (alreadyStopped) expect(session.curve, same(previous));
      await start();
      expect(timer.elapsedSeconds, 0);
      await samples();
      expect(timer.running, isTrue);
      expect(session.curve!.timesMs.last, lessThan(600));
      expect(
        scale.commands.where((c) => c == ScaleCommand.tareAndStartTimer).length,
        2,
      );
      timer.reset();
      expect(timer.elapsedSeconds, 0);
      expect(session.curve, isNull);
    });
  }

  test(
    'quick physical reset is reconciled after command echoes settle',
    () async {
      await start();
      await samples();
      final previous = session.curve;
      scale.emit(0);
      expect(timer.running, isTrue);
      now = now.add(const Duration(seconds: 3));
      scale.emit(0); // No second edge: the old watcher lost this reset.
      expect(timer.running, isFalse);
      expect(timer.elapsedSeconds, 0);
      expect(
        session.curve,
        isNotNull,
      ); // Keep the old curve until explicit Start.
      expect(previous, isNotNull);
      await start();
      await samples();
      expect(timer.running, isTrue);
      expect(session.curve!.weight.last, 15);
      expect(
        scale.commands.where((c) => c == ScaleCommand.tareAndStartTimer).length,
        2,
      );
      expect(session.curve!.timesMs.last, lessThan(600));
    },
  );
  test('a normal pause resumes without clearing or taring', () async {
    await start();
    await samples();
    now = now.add(const Duration(seconds: 3));
    scale.emit(15, timerMs: 400);
    scale.emit(15, timerMs: 400);
    expect(timer.running, isFalse);
    final count = session.curve!.timesMs.length;
    await start();
    await samples();
    expect(session.curve!.timesMs.length, greaterThan(count));
    expect(
      scale.commands.where((c) => c == ScaleCommand.tareAndStartTimer).length,
      1,
    );
  });
  test(
    'disconnect stops recording, preserves curve, and prevents offline Start',
    () async {
      await start();
      await samples();
      final previous = session.curve;
      scale.lose();
      expect(timer.running, isFalse);
      timer.toggle();
      expect(timer.running, isFalse);
      expect(session.curve, same(previous));
      await scale.connect();
      await start();
      await samples();
      expect(timer.running, isTrue);
      expect(
        session.curve!.timesMs.length,
        greaterThan(previous!.timesMs.length),
      );
    },
  );
  test('failed Start stops the app clock and reports the failure', () async {
    scale.reject = true;
    await start();
    expect(timer.running, isFalse);
    expect(session.recording, isFalse);
    expect(session.startFailed, isTrue);
    expect(scale.commands, [ScaleCommand.resetTimer]);
  });
  test('own reset echo followed by ticking does not stop the app', () async {
    await start();
    scale.emit(0);
    scale.emit(0, timerMs: 100);
    now = now.add(const Duration(seconds: 3));
    scale.emit(1, timerMs: 200);
    expect(timer.running, isTrue);
  });
  test(
    'a dial reset before recording does not erase a typed duration',
    () async {
      timer.reset();
      timer.settle(45);
      // An initial reading can contain the previous dial value before Reset applies.
      scale.emit(0, timerMs: 200);
      scale.emit(0);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 3));
      scale.emit(0);
      expect(timer.elapsedSeconds, 45);
      expect(timer.running, isFalse);
    },
  );

  test('tare alone leaves the clock and recording running', () async {
    await start();
    await samples();
    now = now.add(const Duration(seconds: 3));
    scale.emit(0, timerMs: 500);
    expect(timer.running, isTrue);
  });
}
