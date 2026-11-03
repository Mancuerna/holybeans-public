import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_pressure_ble_platform.dart';

class _SlowPressureSensor extends BlePressureSensor {
  _SlowPressureSensor(super.store);
  Completer<void>? startup;
  @override
  Future<void> onNotificationsSubscribed(String id) async {
    await super.onNotificationsSubscribed(id);
    await startup?.future;
  }
}

void main() {
  late FakePressureBlePlatform platform;
  late _SlowPressureSensor sensor;
  late Directory directory;
  const monitor = FoundDevice(id: 'AA:BB', name: 'BOOKOO_EM-1');
  const start = [2, 12, 1, 0, 0, 0, 15];
  const stop = [2, 12, 0, 0, 0, 0, 14];

  setUp(() async {
    platform = FakePressureBlePlatform();
    UniversalBle.setInstance(platform);
    directory = await Directory.systemTemp.createTemp('holybeans-bookoo-ble-');
    sensor = _SlowPressureSensor(
      PairedDeviceFile(File('${directory.path}/sensor.json')),
    );
  });

  tearDown(() async {
    await sensor.disconnect();
    sensor.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'cancelling after subscription still stops pressure transmission',
    () async {
      sensor.startup = Completer<void>();
      final pending = sensor.pair(monitor);
      for (
        var i = 0;
        i < 100 && !platform.events.contains('start:AA:BB');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(platform.events, contains('start:AA:BB'));
      await sensor.disconnect();
      sensor.startup!.complete();
      await pending;
      expect(sensor.connected, isFalse);
      expect(platform.writes.map((write) => write.bytes), [start, stop]);
      expect(await sensor.store.load(), isNull);
    },
  );

  test('subscribes before starting and stops before disconnecting', () async {
    await sensor.pair(monitor);
    expect(sensor.connected, isTrue);
    expect(platform.events, [
      'connect:AA:BB',
      'subscribe:AA:BB',
      'start:AA:BB',
    ]);
    final first = platform.writes.single;
    expect(first.service, '00000fff-0000-1000-8000-00805f9b34fb');
    expect(first.characteristic, '0000ff01-0000-1000-8000-00805f9b34fb');
    expect(first.bytes, start);
    final reading = sensor.readings.first;
    platform.updateCharacteristicValue(
      monitor.id,
      'FF02',
      Uint8List.fromList([2, 27, 0, 0, 3, 142, 85, 0, 0, 0]),
      null,
    );
    expect(await reading, 9.1);
    await sensor.disconnect();
    expect(platform.events.skip(3), ['stop:AA:BB', 'disconnect:AA:BB']);
    expect(platform.writes.map((write) => write.bytes), [start, stop]);
    expect(sensor.bar, isNull);
  });

  test('reconnection restarts transmission without duplicating it', () async {
    await sensor.pair(monitor);
    platform.lose(monitor.id);
    await Future<void>.delayed(Duration.zero);
    expect(sensor.connected, isFalse);
    expect(platform.writes, hasLength(1));
    await sensor.connect(automatic: true);
    await sensor.connect(automatic: true);
    expect(platform.writes.map((write) => write.bytes), [start, start]);
    expect(sensor.connected, isTrue);
  });

  test('changing monitor stops and disconnects the previous one', () async {
    await sensor.pair(monitor);
    await sensor.pair(const FoundDevice(id: 'CC:DD', name: 'BOOKOO_EM-2'));
    expect(platform.events, [
      'connect:AA:BB',
      'subscribe:AA:BB',
      'start:AA:BB',
      'stop:AA:BB',
      'disconnect:AA:BB',
      'connect:CC:DD',
      'subscribe:CC:DD',
      'start:CC:DD',
    ]);
  });

  test('a failed start is not remembered as a successful pairing', () async {
    platform.failStart = true;
    await sensor.pair(monitor);
    expect(sensor.status, DeviceStatus.failed);
    expect(sensor.name, isNull);
    expect(await sensor.store.load(), isNull);
    expect(platform.events.last, 'disconnect:AA:BB');
  });

  test('a failed stop still releases the connection', () async {
    await sensor.pair(monitor);
    platform.failStop = true;
    await sensor.disconnect();
    expect(sensor.connected, isFalse);
    expect(platform.events.last, 'disconnect:AA:BB');
  });

  test(
    'loss during transmission startup is not reported as connected',
    () async {
      platform.loseOnStart = true;
      await sensor.pair(monitor);
      await Future<void>.delayed(Duration.zero);
      expect(sensor.connected, isFalse);
      expect(sensor.name, isNull);
      expect(await sensor.store.load(), isNull);
      expect(platform.writes.map((write) => write.bytes), [start]);
    },
  );
}
