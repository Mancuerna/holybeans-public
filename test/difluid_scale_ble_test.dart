import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/difluid_scale_protocol.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_scale_ble_platform.dart';

void main() {
  late FakeScaleBlePlatform platform;
  late AppDatabase database;
  late BleScale scale;

  setUp(() {
    platform = FakeScaleBlePlatform();
    UniversalBle.setInstance(platform);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    scale = BleScale(ScaleSettings(database));
  });
  tearDown(() async {
    await scale.disconnect();
    scale.dispose();
    await database.close();
  });
  Future<void> pair() async {
    await scale.pair(FoundDevice(id: platform.id, name: platform.name));
    await Future<void>.delayed(Duration.zero);
    expect(scale.connected, isTrue);
  }

  List<List<int>> controls() =>
      platform.writes.where((frame) => frame[2] == 3 && frame[4] == 1).toList();

  test('discovery includes both scale families but not the R2', () async {
    await scale.search();
    await Future<void>.delayed(Duration.zero);
    expect(scale.found.map((device) => device.name), [
      'MB Ti TEST',
      'BOOKOO_SC_U',
    ]);
    expect(
      scale.matchesAdvertisement(
        BleDevice(deviceId: 'unnamed', name: null, services: ['00EE']),
      ),
      isTrue,
    );
    expect(
      scale.advertisedName(
        BleDevice(deviceId: 'unnamed', name: null, services: ['00DD']),
      ),
      'DiFluid Microbalance Ti',
    );
    await scale.stopSearch();
  });

  for (final (ti, alternate) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test(
      'pairing and read-only polling on ti=$ti alternate=$alternate',
      () async {
        platform = FakeScaleBlePlatform(ti: ti, alternate: alternate);
        UniversalBle.setInstance(platform);
        await pair();
        expect(platform.subscriptions.single, (
          platform.service,
          platform.characteristic,
        ));
        expect(platform.events.take(2), [
          'connect:DIFLUID-TEST',
          'subscribe:DIFLUID-TEST',
        ]);
        expect((await scale.settings.load())!.name, platform.name);
        expect(scale.reading!.grams, 18);
        expect(scale.reading!.batteryPercent, 64);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(
          platform.writes.where((frame) => frame[3] == 0),
          hasLength(greaterThan(1)),
        );
        expect(controls(), isEmpty);
        expect(platform.writes.every((frame) => frame[4] == 0), isTrue);
      },
    );
  }

  test(
    'fresh start resets a previous timer, tares, then starts once',
    () async {
      platform.state = 10;
      platform.seconds = 90;
      await pair();
      expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
      expect(platform.state, 10);
      expect(platform.seconds, 0);
      expect(platform.grams, 0);
      expect(platform.tareCount, 1);
      expect(controls(), [
        difluidScaleTimerPause,
        difluidScaleTimerClick,
        difluidScaleTare,
        difluidScaleTimerClick,
      ]);
    },
  );

  test('stop and resume retain weight and do not retare', () async {
    await pair();
    await scale.send(ScaleCommand.tareAndStartTimer);
    platform.emit(281, flow: 5);
    await Future<void>.delayed(Duration.zero);
    expect(scale.reading!.grams, 281);
    expect(scale.reading!.timerRunning, isTrue);
    expect(await scale.send(ScaleCommand.stopTimer), isTrue);
    expect(platform.state, 11);
    expect(await scale.send(ScaleCommand.startTimer), isTrue);
    expect(platform.state, 10);
    expect(platform.grams, 281);
    expect(platform.tareCount, 1);
    final count = controls().length;
    expect(await scale.send(ScaleCommand.startTimer), isTrue);
    expect(
      controls(),
      hasLength(count),
      reason: 'Start must never toggle a running timer off',
    );
  });

  test(
    'DiFluid auto-stop cannot finish an espresso before its first real flow',
    () async {
      await pair();
      var now = DateTime(2026, 10, 27);
      final session = BrewScaleSession(scale, clock: () => now);
      addTearDown(session.dispose);
      var stops = 0;
      int? stopAt;
      session
        ..isEspresso = (() => true)
        ..doseGrams = (() => 18)
        ..requestStart = (() => session.timerStarted(0))
        ..requestStop = ((seconds) {
          stops++;
          stopAt = seconds;
          session.timerStopped();
        });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      session.waitForDrip();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (final grams in [0.0, 0.1, 1.2, 1.5, 2.0]) {
        platform.emit(grams);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session.recording, isTrue);
      now = now.add(const Duration(seconds: 3));
      platform.publishStatus(10);
      platform.seconds = 2;
      platform.emit(2);
      await Future<void>.delayed(Duration.zero);
      platform.publishStatus(14);
      platform.emit(2);
      await Future<void>.delayed(Duration.zero);
      expect(stops, 0);
      expect(session.recording, isTrue);
      platform.seconds = 0;
      platform.publishStatus(13);
      platform.emit(2);
      await Future<void>.delayed(Duration.zero);
      expect(
        stops,
        0,
        reason: 'the automatic result may later clear its clock',
      );
      platform.publishStatus(11);
      platform.emit(2);
      await Future<void>.delayed(Duration.zero);
      expect(stops, 1, reason: 'an explicit pause still stops the brew');
      expect(stopAt, isNull, reason: 'manual pause must retain the result');
      expect(session.recording, isFalse);
      platform.publishStatus(10);
      platform.seconds = 1;
      platform.emit(2);
      await Future<void>.delayed(Duration.zero);
      expect(session.recording, isTrue, reason: 'the next start still works');
      expect(
        platform.writes.where((f) => f[2] == 1).every((f) => f[4] == 0),
        isTrue,
      );
    },
  );

  test('Start waits for the scale to finish taring before timing', () async {
    await pair();
    platform.tareReadyAfterReads = 4;
    expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
    expect(platform.state, 10);
    expect(platform.tareCount, 1);
    expect(controls(), [difluidScaleTare, difluidScaleTimerClick]);
  });

  test(
    'resume checks whether the first click already restarted timing',
    () async {
      platform.resumeFromPause = true;
      platform.state = 11;
      await pair();
      expect(await scale.send(ScaleCommand.startTimer), isTrue);
      expect(controls(), [difluidScaleTimerClick]);
      expect(platform.state, 10);
    },
  );

  test(
    'reset never starts an idle scale and never changes its weight',
    () async {
      await pair();
      expect(await scale.send(ScaleCommand.resetTimer), isTrue);
      expect(controls(), isEmpty);
      platform.state = 10;
      platform.seconds = 50;
      expect(await scale.send(ScaleCommand.resetTimer), isTrue);
      expect(platform.state, 5);
      expect(platform.seconds, 0);
      expect(platform.grams, 18);
      expect(controls(), [difluidScaleTimerPause, difluidScaleTimerClick]);
    },
  );

  test(
    'unsupported status and failed writes cannot toggle other functions',
    () async {
      await pair();
      platform.state = 8;
      expect(await scale.send(ScaleCommand.tareAndStartTimer), isFalse);
      expect(controls(), isEmpty);
      platform.state = 5;
      platform.failNextControl = true;
      expect(await scale.send(ScaleCommand.tare), isFalse);
      expect(await scale.send(ScaleCommand.tare), isTrue);
      expect(platform.tareCount, 1);
    },
  );

  test('a channel without valid status replies is not remembered', () async {
    platform.respondToStatus = false;
    await scale.pair(FoundDevice(id: platform.id, name: platform.name));
    expect(scale.status, DeviceStatus.failed);
    expect(await scale.settings.load(), isNull);
    expect(controls(), isEmpty);
  });

  test(
    'a new app instance reconnects using the remembered DiFluid identity',
    () async {
      await pair();
      final settings = scale.settings;
      await scale.disconnect();
      scale.dispose();
      scale = BleScale(settings);
      await scale.load();
      expect(scale.name, platform.name);
      await scale.connect(automatic: true);
      expect(scale.connected, isTrue);
      expect(platform.subscriptions.last, (
        platform.service,
        platform.characteristic,
      ));
      expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
    },
  );

  test(
    'loss cancels reads, reconnect restores them and forgetting persists',
    () async {
      await pair();
      platform.lose(platform.id);
      await Future<void>.delayed(Duration.zero);
      final count = platform.writes.length;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(platform.writes, hasLength(count));
      expect(scale.reading, isNull);
      await scale.connect(automatic: true);
      expect(scale.connected, isTrue);
      await scale.forget();
      expect(await scale.settings.load(), isNull);
    },
  );

  test('weight polling survives status write failures', () async {
    await pair();
    platform.failStatusWrites = true;
    int dataWrites() => platform.writes.where((frame) => frame[3] == 0).length;
    final before = dataWrites();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(dataWrites(), greaterThan(before));
  });
  test('weight polling continues while tare waits for the scale', () async {
    await pair();
    platform.tareReadyAfterReads = 20;
    final command = scale.send(ScaleCommand.tareAndStartTimer);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    int dataWrites() => platform.writes.where((frame) => frame[3] == 0).length;
    final before = dataWrites();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(dataWrites(), greaterThan(before));
    expect(await command, isTrue);
  });
  test(
    'BOOKOO retains its protocol and serializes fresh-start commands',
    () async {
      await scale.pair(
        const FoundDevice(id: 'BOOKOO-TEST', name: 'BOOKOO_SC_U'),
      );
      final first = scale.send(ScaleCommand.resetTimer);
      final second = scale.send(ScaleCommand.tareAndStartTimer);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(platform.writes, [
        [3, 10, 6, 0, 0, 15],
        [3, 10, 7, 0, 0, 14],
      ]);
    },
  );
}
