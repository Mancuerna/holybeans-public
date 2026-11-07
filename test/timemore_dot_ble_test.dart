import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_dot_ble_platform.dart';
import 'helpers/fake_scale_ble_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FakeDotBlePlatform platform;
  late BleScale scale;
  late List<Map<String, dynamic>> traces;
  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    platform = FakeDotBlePlatform();
    UniversalBle.setInstance(platform);
    traces = [];
    scale = BleScale(
      ScaleSettings(database),
      trace: (event, data) {
        traces.add({'event': event, 'data': data});
      },
    );
  });
  tearDown(() async {
    await scale.disconnect();
    scale.dispose();
    await database.close();
  });
  Future<void> connect() =>
      scale.pair(FoundDevice(id: platform.id, name: platform.name));
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<List<Map<String, dynamic>>> export() async => traces;

  test(
    'timer ACK applies the requested action, not its success byte',
    () async {
      await connect();
      platform.emit(10);
      await settle();
      expect(scale.reading!.timerRunning, isFalse);
      for (final (command, running) in [
        (ScaleCommand.startTimer, true),
        (ScaleCommand.stopTimer, false),
        (ScaleCommand.startTimer, true),
        (ScaleCommand.resetTimer, false),
      ]) {
        expect(await scale.send(command), isTrue);
        platform.emit(10);
        await settle();
        expect(scale.reading!.timerRunning, running);
      }
      platform.acceptCommand = false;
      expect(await scale.send(ScaleCommand.startTimer), isFalse);
      platform.emit(10);
      await settle();
      expect(scale.reading!.timerRunning, isFalse);
      // An unsolicited ACK has no request to associate with a timer state.
      platform.publish(dotReply(3, 2, [1]));
      platform.emit(10);
      await settle();
      expect(scale.reading!.timerRunning, isFalse);
    },
  );

  test('replays captured v1.0.4 weights and all five control ACKs', () async {
    platform.answerQueries = false;
    platform.acknowledge = false;
    await connect();
    final capture = jsonDecode(
      File('test/fixtures/timemore_dot_controls_v104.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final readings = <ScaleReading>[];
    final subscription = scale.readings.listen(readings.add);
    addTearDown(subscription.cancel);
    Future<bool>? pending;
    var commands = 0;
    for (final event in capture['events'] as List<dynamic>) {
      final row = event as Map<String, dynamic>;
      if (row['command'] case final String name) {
        if (pending != null) expect(await pending, isTrue);
        pending = scale.send(ScaleCommand.values.byName(name));
        commands++;
        await settle();
      } else {
        final bytes = Uint8List.fromList(
          (row['hex'] as String)
              .split(' ')
              .map((b) => int.parse(b, radix: 16))
              .toList(),
        );
        for (var i = 0; i < (row['count'] as int); i++) {
          platform.publish(bytes);
          await settle();
        }
      }
    }
    expect(await pending!, isTrue);
    expect(commands, 5);
    expect(readings, hasLength(247));
    expect(readings.map((r) => r.grams), containsAll([-55.0, 69.2]));
    expect(readings.map((r) => r.batteryPercent).toSet(), {100});
    expect(
      readings
          .where((r) => r.timerMs > 0 && r.timerMs < 10000)
          .every((r) => r.timerRunning == true),
      isTrue,
    );
    expect(
      readings.any((r) => r.timerMs == 10000 && r.timerRunning == false),
      isTrue,
    );
    expect(readings.last.timerMs, 0);
    expect(readings.last.timerRunning, isFalse);
  });

  test('fresh start serializes tare, reset and start', () async {
    await connect();
    expect(await scale.send(ScaleCommand.tareAndStartTimer), isTrue);
    expect(
      platform.writes
          .where((p) => p[2] == 3)
          .map((p) => [p[3], ...p.sublist(6, p.length - 2)]),
      [
        [13],
        [2, 3],
        [2, 1],
      ],
    );
    platform.emit(0);
    await settle();
    expect(scale.reading!.timerRunning, isTrue);
  });

  test('discovers unnamed Dot and verifies identity before bonding', () async {
    await scale.search();
    await settle();
    expect(scale.found.single.id, platform.id);
    await scale.pair(scale.found.single);
    expect(scale.connected, isTrue);
    expect(
      platform.events.indexOf('bond'),
      greaterThan(
        platform.events.indexOf('read:00002a29-0000-1000-8000-00805f9b34fb'),
      ),
    );
    expect(platform.writes.map((p) => (p[2], p[3])), [(2, 6), (2, 5), (2, 2)]);
    platform.emit(42.3, flow: 2.5);
    await settle();
    expect(scale.reading!.grams, 42.3);
    expect(scale.reading!.batteryPercent, 76);
    expect(scale.rememberedScales.single.id, platform.id);
  });

  test('recognizes Dot names without claiming other named FFF0 devices', () {
    for (final name in [
      'TIMEMORE_Dot',
      'TIMEMORE DOT',
      'TES017',
      'Timemore Black Mirror DOT',
    ]) {
      expect(scale.matchesName(name), isTrue, reason: name);
    }
    expect(
      scale.matchesAdvertisement(
        BleDevice(deviceId: 'other', name: 'Other sensor', services: ['FFF0']),
      ),
      isFalse,
    );
  });

  test('shared FFF0 service with wrong identity cannot send or bond', () async {
    platform.model = 'OTHER';
    await connect();
    expect(scale.status, DeviceStatus.failed);
    expect(platform.writes, isEmpty);
    expect(platform.events, isNot(contains('bond')));
    expect((await export()).map((r) => r['event']), contains('connect.error'));
  });

  test(
    'identified v1.0.4 accepts reserved CRC and confirms controls',
    () async {
      platform.reservedZeroCrc = true;
      await connect();
      platform.emit(646.3);
      await settle();
      expect(scale.reading!.grams, 646.3);
      expect(scale.reading!.batteryPercent, 76);
      for (final command in [
        ScaleCommand.tare,
        ScaleCommand.startTimer,
        ScaleCommand.stopTimer,
        ScaleCommand.resetTimer,
      ]) {
        expect(await scale.send(command), isTrue);
      }
      final rows = await export();
      expect(
        rows.where((row) => row['event'] == 'dot.crc.policy').single['data'],
        {'firmware': 'v1.0.4', 'allowReservedZero': true},
      );
      expect(
        rows
            .where((row) => row['event'] == 'dot.frame')
            .map((row) => row['data']['crc']),
        everyElement('reservedZero'),
      );
      // A new connection must not inherit the old firmware exception or unit.
      await scale.disconnect();
      platform.firmware = 'v1.0.5';
      await connect();
      platform.emit(42.3);
      await settle();
      expect(scale.reading, isNull);
    },
  );

  for (final firmware in ['v1.0.5', null]) {
    test('firmware $firmware keeps strict CRC validation', () async {
      platform.firmware = firmware;
      platform.reservedZeroCrc = true;
      await connect();
      platform.emit(42.3);
      await settle();
      expect(scale.reading, isNull);
      final rows = await export();
      expect(rows.where((r) => r['event'] == 'dot.rejected'), hasLength(4));
      expect(
        rows
            .where((r) => r['event'] == 'dot.crc.policy')
            .single['data']['allowReservedZero'],
        isFalse,
      );
      // Real CRCs remain supported, including when firmware cannot be read.
      platform.reservedZeroCrc = false;
      platform.publish(dotReply(2, 6, [0]));
      platform.emit(42.3);
      await settle();
      expect(scale.reading!.grams, 42.3);
    });
  }

  test('bond failure leaves an exportable error and no commands', () async {
    platform.bondSucceeds = false;
    await connect();
    expect(scale.status, DeviceStatus.failed);
    expect(platform.writes, isEmpty);
    expect((await export()).map((r) => r['event']), contains('connect.error'));
  });

  test(
    'silent firmware and ounces preserve raw packets without fabricated grams',
    () async {
      platform.answerQueries = false;
      await connect();
      expect(scale.connected, isTrue);
      platform.emit(18);
      await settle();
      expect(scale.reading, isNull);
      platform.publish(dotReply(1, 6, [1]));
      platform.emit(18);
      await settle();
      expect(scale.reading, isNull);
      final rows = await export();
      expect(rows.where((r) => r['event'] == 'notification.raw'), hasLength(3));
      expect(
        rows.where((r) => r['event'] == 'dot.reading.skipped'),
        hasLength(2),
      );
    },
  );

  test('write with response fallback and rejected ACK are reported', () async {
    platform.writeWithResponseOnly = true;
    await connect();
    platform.acceptCommand = false;
    expect(await scale.send(ScaleCommand.startTimer), isFalse);
    platform.acceptCommand = true;
    expect(await scale.send(ScaleCommand.stopTimer), isTrue);
    platform.failWrite = true;
    expect(await scale.send(ScaleCommand.tare), isFalse);
  });

  test('missing ACK is not success and does not retry the command', () async {
    await connect();
    platform.acknowledge = false;
    expect(await scale.send(ScaleCommand.tare), isFalse);
    platform.acknowledge = true;
    expect(await scale.send(ScaleCommand.startTimer), isFalse);
    expect(platform.writes.where((p) => p[2] == 3), hasLength(1));
    expect(
      (await export()).map((r) => r['event']),
      contains('dot.ack.timeout'),
    );
  });

  test(
    'disconnect cancels a compound command and reconnect clears parser state',
    () async {
      await connect();
      platform.acknowledge = false;
      final pending = scale.send(ScaleCommand.tareAndStartTimer);
      await settle();
      await scale.disconnect();
      expect(await pending, isFalse);
      expect(platform.writes.where((p) => p[2] == 3), hasLength(1));
      platform.unit = 1;
      await connect();
      platform.emit(18);
      await settle();
      expect(scale.reading, isNull);
      expect(platform.events.where((e) => e == 'bond'), hasLength(1));
    },
  );

  test('switching from Dot to DiFluid clears the Dot adapter', () async {
    await connect();
    final difluid = FakeScaleBlePlatform();
    UniversalBle.setInstance(difluid);
    await scale.pair(FoundDevice(id: difluid.id, name: difluid.name));
    expect(scale.connected, isTrue);
    expect(await scale.send(ScaleCommand.tare), isTrue);
    expect(difluid.tareCount, 1);
  });
}
