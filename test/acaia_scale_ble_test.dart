@Tags(['slow'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_acaia_ble_platform.dart';

void main() {
  group('captured Pearl startup', () {
    late FakeAcaiaBlePlatform platform;
    late AppDatabase db;
    late BleScale scale;
    final trace = <(String, Map<String, Object?>)>[];
    setUp(() {
      platform = FakeAcaiaBlePlatform(pearl: true)
        ..settingsDelay = const Duration(milliseconds: 250);
      UniversalBle.setInstance(platform);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      trace.clear();
      scale = BleScale(
        ScaleSettings(db),
        trace: (event, data) => trace.add((event, data)),
      );
    });
    tearDown(() async {
      await scale.disconnect();
      scale.dispose();
      await db.close();
    });
    test('Android wake-up precedes the Pearl S handshake', () async {
      platform.requiresAndroidWakeUp = true;
      await scale.pair(FoundDevice(id: platform.id, name: 'PEARLS-TEST'));
      expect(scale.connected, isTrue);
      expect(platform.wakeUps, [
        [0, 1],
      ]);
      expect(platform.wakeUpProperties, [BleOutputProperty.withResponse]);
      expect(platform.writes.take(3).map((frame) => frame[2]), [11, 12]);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(
        platform.writes.where((frame) => frame[2] == 11).length,
        greaterThan(1),
      );
    });
    test(
      'subscribes even when identification does not return settings',
      () async {
        platform
          ..settingsAfterSubscription = true
          ..ignoreAcknowledgedHandshake = true;
        await scale.pair(FoundDevice(id: platform.id, name: 'PEARLS-TEST'));
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, 18);
        expect(platform.writes.map((frame) => frame[2]), [11, 12]);
        await scale.disconnect();
        platform.grams = 42;
        await scale.connect();
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, 42);
      },
    );
    test(
      'late settings still require a decoded reading before connected',
      () async {
        platform
          ..sendSettings = false
          ..sendWeights = false;
        final pairing = scale.pair(
          FoundDevice(id: platform.id, name: platform.name),
        );
        await platform.notificationRequest.future.timeout(
          const Duration(seconds: 2),
        );
        platform.emit(18);
        await Future<void>.delayed(Duration.zero);
        expect(scale.connected, isFalse);
        expect(scale.reading, isNull);
        platform.reply(8, [9, 64, 5, 2, 1, 0, 1, 1, 0]);
        await Future<void>.delayed(Duration.zero);
        expect(scale.connected, isFalse);
        expect(scale.reading, isNull);
        platform.emit(2);
        await pairing;
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, closeTo(56.69904625, 0.000001));
      },
    );
    test(
      'handshake uses unacknowledged writes on a dual-mode Pearl S channel',
      () async {
        platform.ignoreAcknowledgedHandshake = true;
        await scale.pair(FoundDevice(id: platform.id, name: 'PEARLS-TEST'));
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, 18);
        expect(platform.writeProperties.take(2), [
          BleOutputProperty.withoutResponse,
          BleOutputProperty.withoutResponse,
        ]);
        expect(platform.writes.map((frame) => frame[2]), [11, 12]);
        await scale.disconnect();
        platform.grams = 42;
        await scale.connect();
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, 42);
        expect(await scale.send(ScaleCommand.tare), isTrue);
        expect(platform.tareCount, 1);
        expect(
          platform.writeProperties.last,
          BleOutputProperty.withoutResponse,
        );
      },
    );
    test('waits for real settings and receives weights without the stalled long write', () async {
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      expect(scale.connected, isTrue);
      expect(scale.reading!.grams, 18);
      expect(scale.reading!.batteryPercent, 73);
      expect(platform.writes.every((bytes) => bytes.length <= 20), isTrue);
      expect(platform.writes.any((bytes) => bytes[2] == 6), isFalse);
      expect(platform.writeProperties, [
        BleOutputProperty.withoutResponse,
        BleOutputProperty.withoutResponse,
      ]);
      expect(
        trace.where((event) => event.$1 == 'acaia.write.ok'),
        hasLength(3),
      );
      expect(
        trace
            .where((event) => event.$1 == 'acaia.write.ok')
            .every((event) => event.$2['durationUs'] is int),
        isTrue,
      );
      expect(
        trace
            .where((event) => event.$1 == 'acaia.write.ok')
            .map((event) => event.$2['withResponse']),
        [true, false, false],
      );
    });
    test(
      'weight without unit settings never counts as a ready scale',
      () async {
        platform.sendSettings = false;
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        expect(scale.connected, isFalse);
        expect(scale.reading, isNull);
        expect(await scale.settings.load(), isNull);
        expect(platform.notificationsRequested, isTrue);
      },
    );
    test(
      'disconnect while waiting for settings stops startup and heartbeat',
      () async {
        platform.sendSettings = false;
        final pairing = scale.pair(
          FoundDevice(id: platform.id, name: platform.name),
        );
        await platform.notificationRequest.future.timeout(
          const Duration(seconds: 2),
        );
        await scale.disconnect();
        await pairing;
        expect(scale.connected, isFalse);
        expect(await scale.settings.load(), isNull);
        final writes = platform.writes.length;
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        expect(platform.writes.length, writes);
        platform
          ..sendSettings = true
          ..settingsAfterSubscription = true;
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        expect(scale.connected, isTrue);
        expect(scale.reading!.grams, 18);
      },
    );
    test('settings alone never count as a ready scale', () async {
      platform.sendWeights = false;
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      expect(scale.connected, isFalse);
      expect(scale.reading, isNull);
      expect(await scale.settings.load(), isNull);
      expect(platform.writes.any((bytes) => bytes[2] == 0), isTrue);
    });
    test(
      'startup requests notifications without an initial heartbeat',
      () async {
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        expect(scale.connected, isTrue);
        expect(platform.writes.map((frame) => frame[2]), [11, 12]);
      },
    );
    test(
      'silent recovery repeats identification and subscription only',
      () async {
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        platform.respond = false;
        final initialWrites = platform.writes.length;
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        final recovery = platform.writes.skip(initialWrites).toList();
        expect(recovery.map((frame) => frame[2]), containsAllInOrder([11, 12]));
        expect(recovery.where((frame) => frame[2] == 0), isEmpty);
      },
    );
    test('a received notification drives the due heartbeat', () async {
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      final initialHeartbeats = platform.writes
          .where((frame) => frame[2] == 0)
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      platform.emit(22);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        platform.writes.where((frame) => frame[2] == 0).length,
        initialHeartbeats + 1,
      );
      expect(platform.writeProperties.skip(2), [
        BleOutputProperty.withResponse,
        BleOutputProperty.withResponse,
      ]);
    });
    test('modern timer controls use unacknowledged writes', () async {
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      final initialWrites = platform.writeProperties.length;
      expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
      expect(
        platform.writeProperties.skip(initialWrites),
        everyElement(BleOutputProperty.withoutResponse),
      );
    });
    test('wake-up failure is traced but does not skip the handshake', () async {
      platform.failWakeUp = true;
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      expect(scale.connected, isTrue);
      expect(
        trace.where(
          (event) =>
              event.$1 == 'acaia.write.error' && event.$2['bytes'] == '00 01',
        ),
        hasLength(1),
      );
    });
    test('startup requests and traces MTU 247', () async {
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      expect(platform.mtuRequests, [(platform.id, 247)]);
      expect(
        trace.where(
          (event) => event.$1 == 'acaia.mtu.ok' && event.$2['mtu'] == 247,
        ),
        hasLength(1),
      );
    });
    test('MTU failure is traced without blocking the handshake', () async {
      platform.failMtu = true;
      await scale.pair(FoundDevice(id: platform.id, name: platform.name));
      expect(platform.mtuRequests, [(platform.id, 247)]);
      expect(scale.connected, isTrue);
      expect(
        trace.where((event) => event.$1 == 'acaia.mtu.error'),
        hasLength(1),
      );
    });
  });
  for (final classic in [false, true]) {
    group('classic=$classic', () {
      late FakeAcaiaBlePlatform platform;
      late AppDatabase db;
      late BleScale scale;
      setUp(() {
        platform = FakeAcaiaBlePlatform(classic: classic);
        UniversalBle.setInstance(platform);
        db = AppDatabase.forTesting(NativeDatabase.memory());
        scale = BleScale(ScaleSettings(db));
      });
      tearDown(() async {
        await scale.disconnect();
        scale.dispose();
        await db.close();
      });
      Future<void> pair() async {
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        await Future<void>.delayed(Duration.zero);
      }

      test(
        'Acaia classic=$classic discovers, validates readings and only controls on request',
        () async {
          await scale.search();
          await Future<void>.delayed(Duration.zero);
          expect(scale.found.map((d) => d.name), contains(platform.name));
          await pair();
          expect(scale.connected, isTrue);
          expect(scale.reading!.grams, 18);
          expect(platform.writes.map((b) => b[2]), [11, 12]);
          expect(
            platform.writeProperties,
            everyElement(
              classic
                  ? BleOutputProperty.withResponse
                  : BleOutputProperty.withoutResponse,
            ),
          );
          expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
          expect(platform.writes.skip(2).map((b) => b[2]), [13, 13, 4, 13]);
          expect(platform.tareCount, 1);
          await scale.send(ScaleCommand.stopTimer);
          await scale.send(ScaleCommand.startTimer);
          expect(platform.tareCount, 1);
          platform.failControl = true;
          expect(await scale.send(ScaleCommand.tare), isFalse);
          platform.failControl = false;
          expect(await scale.send(ScaleCommand.tare), isTrue);
        },
      );
      test(
        'clock traffic cannot start or restart a brew; physical Start can',
        () async {
          await pair();
          var now = DateTime(2026, 10, 30);
          final session = BrewScaleSession(scale, clock: () => now);
          addTearDown(session.dispose);
          var starts = 0;
          session
            ..requestStart = (() {
              starts++;
              session.timerStarted(0);
            })
            ..requestStop = ((_) => session.timerStopped());
          Future<void> readings() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            now = now.add(const Duration(seconds: 3));
            for (var second = 1; second <= 4; second++) {
              platform.seconds = second;
              platform.emit(second.toDouble());
              await Future<void>.delayed(Duration.zero);
            }
          }

          await readings();
          expect(starts, 0);
          expect(session.recording, isFalse);
          platform.button(8);
          await Future<void>.delayed(Duration.zero);
          expect(starts, 1);
          expect(session.recording, isTrue);
          session.timerStopped();
          await readings();
          expect(starts, 1);
          expect(session.recording, isFalse);
          session.timerReset();
          await readings();
          expect(starts, 1);
          expect(session.recording, isFalse);
          platform.button(8);
          await Future<void>.delayed(Duration.zero);
          expect(starts, 2);
          expect(session.recording, isTrue);
        },
      );
      test(
        'first drip survives a stagnant clock and physical Stop still works',
        () async {
          await pair();
          var now = DateTime(2026, 10, 27);
          final session = BrewScaleSession(scale, clock: () => now);
          addTearDown(session.dispose);
          var stops = 0;
          session
            ..isEspresso = (() => true)
            ..doseGrams = (() => 18)
            ..requestStart = (() => session.timerStarted(0))
            ..requestStop = ((_) {
              stops++;
              session.timerStopped();
            });
          await Future<void>.delayed(const Duration(milliseconds: 100));
          session.waitForDrip();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          platform.seconds = 2;
          platform.emit(0);
          await Future<void>.delayed(Duration.zero);
          expect(session.recording, isFalse);
          for (final g in [0.0, 0.1, 1.2, 1.5, 2.0]) {
            platform.emit(g);
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(session.recording, isTrue);
          now = now.add(const Duration(seconds: 3));
          for (var i = 0; i < 5; i++) {
            platform.emit(2);
          }
          await Future<void>.delayed(Duration.zero);
          expect(stops, 0);
          platform.button(10);
          platform.emit(2);
          await Future<void>.delayed(Duration.zero);
          expect(stops, 1);
          expect(session.recording, isFalse);
        },
      );
      test(
        'Acaia classic=$classic closes heartbeat and resets decoder on reconnect',
        () async {
          await pair();
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          platform.emit(19);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(platform.writes.where((b) => b[2] == 0), hasLength(1));
          platform.loseConnection();
          await Future<void>.delayed(Duration.zero);
          expect(scale.connected, isFalse);
          expect(scale.reading, isNull);
          final count = platform.writes.length;
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(platform.writes.length, count);
          platform.grams = 42;
          await scale.connect();
          expect(scale.connected, isTrue);
          expect(scale.reading!.grams, 42);
        },
      );
      test(
        'Acaia classic=$classic silent device is not remembered as connected',
        () async {
          platform.respond = false;
          await pair();
          expect(scale.connected, isFalse);
          expect(await scale.settings.load(), isNull);
          final count = platform.writes.length;
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(platform.writes.length, count);
        },
      );
    });
  }
}
