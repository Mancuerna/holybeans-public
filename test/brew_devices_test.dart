import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

import 'helpers/fake_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BrewDraft draft;
  late BrewTimer timer;
  late FakeScale scale;

  setUp(() {
    draft = BrewDraft();
    timer = BrewTimer(
      minutes: TextEditingController(),
      seconds: TextEditingController(),
    );
    scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
  });

  tearDown(() {
    timer.dispose();
    draft.dispose();
    scale.dispose();
  });

  for (final espresso in [false, true]) {
    test('saved scale doses fill the form (espresso: $espresso)', () {
      scale.emitDose(15); // A dose saved before opening is not reused.
      draft.dose.text = '17';
      var measurements = 0;
      final devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => espresso,
        scale: scale,
        onMeasurement: () => measurements++,
      );
      expect(draft.dose.text, '17');
      scale.emitDose(18.2);
      expect(draft.dose.text, '18.2');
      expect(measurements, 1);
      expect(timer.running, isFalse);
      expect(devices.curve, isNull);

      draft.dose.text = '19';
      scale.emit(36);
      expect(draft.dose.text, '19');
      for (final invalid in [0.0, -18.0, double.nan, double.infinity]) {
        scale.emitDose(invalid);
      }
      expect(draft.dose.text, '19');
      scale.emitDose(20);
      expect(draft.dose.text, '20');
      expect(measurements, 2);

      devices.dispose();
      scale.emitDose(21);
      expect(draft.dose.text, '20');
    });
  }

  /// Records a shot that ends on [grams], then [lifted] readings after the
  /// cup came off the scale, and stops it.
  Future<BrewDevices> shot(
    double grams, {
    required bool espresso,
    List<double> lifted = const [],
  }) async {
    final devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => espresso,
      scale: scale,
    );
    devices.timerStarted(0);
    for (final weight in [0.0, 12.0, 30.0, grams, ...lifted]) {
      scale.emit(weight);
      // The recording keeps a reading every 100 ms at most.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    devices.timerStopped();
    return devices;
  }

  test('an espresso takes its yield from the scale, even with the cup '
      'lifted off before stopping', () async {
    final devices = await shot(36.4, espresso: true);
    expect(draft.beverage.text, '36.4');
    devices.dispose();

    draft.beverage.clear();
    final lifted = await shot(36.4, espresso: true, lifted: [-310, -310]);
    expect(draft.beverage.text, '36.4');
    lifted.dispose();
  });

  test('a yield written by hand stays, and filter is left alone', () async {
    draft.beverage.text = '38';
    final espresso = await shot(36.4, espresso: true);
    expect(draft.beverage.text, '38');
    espresso.dispose();

    draft.beverage.clear();
    final filter = await shot(250, espresso: false);
    expect(draft.beverage.text, isEmpty);
    filter.dispose();
  });

  test(
    'a transient load cannot replace espresso yield or inflate its curve',
    () async {
      final devices = await shot(
        47.2,
        espresso: true,
        lifted: [252, 206, 47.9],
      );
      expect(draft.beverage.text, '47.9');
      expect(devices.curve!.weight, isNot(contains(252)));
      expect(devices.curve!.weight, isNot(contains(206)));
      expect(devices.curve!.weight.last, 47.9);
      devices.dispose();
    },
  );

  test(
    'old load before tare does not become the espresso guard baseline',
    () async {
      final devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => true,
        scale: scale,
      );
      devices.timerStarted(0);
      for (final grams in [350.0, 0.0, 12.0, 36.0]) {
        scale.emit(grams);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      devices.timerStopped();
      expect(draft.beverage.text, '36');
      expect(devices.curve!.weight.first, 0);
      devices.dispose();
    },
  );

  test(
    'a physical reset keeps an aborted attempt out of the next result',
    () async {
      timer.dispose();
      late final BrewDevices devices;
      timer = BrewTimer(
        minutes: draft.durationMinutes,
        seconds: draft.durationSeconds,
        onStart: (seconds) => devices.timerStarted(seconds),
        onStop: () => devices.timerStopped(),
        onReset: () => devices.timerReset(),
      );
      devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => true,
        scale: scale,
      );
      timer.toggle();
      await Future<void>.delayed(Duration.zero);
      scale.emit(0, timerMs: 100);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      scale.emit(12, timerMs: 200);
      scale.emit(0);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      scale.emit(0);
      expect(timer.running, isFalse);
      expect(draft.beverage.text, isEmpty);
      expect(devices.curve, isNotNull);
      timer.toggle();
      await Future<void>.delayed(Duration.zero);
      for (final grams in [0.0, 12.0, 36.0]) {
        scale.emit(grams);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      timer.stop();
      expect(draft.beverage.text, '36');
      devices.dispose();
    },
  );

  test('scale requestStart cannot bypass duration validation', () {
    timer.dispose();
    late final BrewDevices devices;
    var starts = 0;
    timer = BrewTimer(
      minutes: draft.durationMinutes,
      seconds: draft.durationSeconds,
      onStart: (seconds) {
        starts++;
        devices.timerStarted(seconds);
      },
    );
    devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => true,
      scale: scale,
    );
    draft.durationSeconds.text = '75';
    final commandsBeforeInvalidStart = [...scale.commands];

    devices.scale!.requestStart!();

    expect(starts, 0);
    expect(timer.running, isFalse);
    expect(draft.durationSeconds.text, '75');
    expect(devices.scale!.recording, isFalse);
    expect(scale.commands, commandsBeforeInvalidStart);
    devices.dispose();
  });

  test('a shot end noticed late stops the timer at its real time', () {
    final devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => true,
      scale: scale,
    );
    timer.toggle();
    devices.scale!.requestStop!(27);
    expect((timer.running, timer.elapsedSeconds), (false, 27));
    devices.dispose();
  });

  test(
    'a paired scale that does not answer leaves the timer to run alone',
    () async {
      final absent = _UnreachableScale();
      addTearDown(absent.dispose);
      timer.dispose();
      late final BrewDevices devices;
      timer = BrewTimer(
        minutes: draft.durationMinutes,
        seconds: draft.durationSeconds,
        onStart: (seconds) => devices.timerStarted(seconds),
        onStop: () => devices.timerStopped(),
        onReset: () => devices.timerReset(),
      );
      devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => true,
        scale: absent,
      );
      addTearDown(devices.dispose);
      absent
        ..status = DeviceStatus.connecting
        ..notifyListeners();
      // Waits while it is still connecting, so its curve is not lost.
      expect(timer.canStart, isFalse);
      absent
        ..status = DeviceStatus.failed
        ..notifyListeners();
      expect(timer.canStart, isTrue);
      timer.toggle();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(timer.running, isTrue);
      timer.stop();
      expect(timer.elapsedSeconds, greaterThanOrEqualTo(1));
      expect(devices.curve, isNull);
      expect(absent.commands, isEmpty);
    },
  );
}

/// Paired, but switched off or out of battery: connecting never succeeds.
class _UnreachableScale extends FakeScale {
  _UnreachableScale() : super(name: 'BOOKOO_SC_U');

  @override
  Future<void> connect({bool automatic = false}) async {
    status = DeviceStatus.failed;
    notifyListeners();
  }
}
