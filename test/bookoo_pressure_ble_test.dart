import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/domain/bookoo_pressure_protocol.dart';
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

class _BusyPressurePlatform extends FakePressureBlePlatform {
  final readEntered = Completer<void>();
  final releaseRead = Completer<void>();
  final stopEntered = Completer<void>();
  final releaseStop = Completer<void>();
  bool holdStop = false;

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    readEntered.complete();
    await releaseRead.future;
    return Uint8List(0);
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (holdStop && value[2] == 0 && !stopEntered.isCompleted) {
      stopEntered.complete();
      await releaseStop.future;
    }
    await super.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty,
    );
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

  test('another device cannot block pressure connection or recovery', () async {
    final busy = _BusyPressurePlatform();
    UniversalBle.setInstance(busy);
    final otherRead = UniversalBle.read('SCALE', 'FFF0', 'FFF1');
    await busy.readEntered.future;
    try {
      await sensor.pair(monitor).timeout(const Duration(seconds: 1));
      final reading = sensor.readings.first;
      busy.updateCharacteristicValue(
        monitor.id,
        BookooPressureUuids.pressure,
        Uint8List.fromList([2, 27, 0, 0, 3, 142, 85, 0, 0, 0]),
        null,
      );
      expect(await reading, 9.1);
      await sensor.disconnect().timeout(const Duration(seconds: 1));
      await sensor.connect().timeout(const Duration(seconds: 1));
      expect(sensor.connected, isTrue);
      expect(busy.writes.map((write) => write.bytes), [start, stop, start]);
      expect(busy.releaseRead.isCompleted, isFalse);
    } finally {
      busy.releaseRead.complete();
      await otherRead;
    }
  });

  test(
    'pressure commands still serialize behind work on the same device',
    () async {
      final busy = _BusyPressurePlatform();
      UniversalBle.setInstance(busy);
      await sensor.pair(monitor);
      final read = UniversalBle.read(monitor.id, '0FFF', 'FF03');
      await busy.readEntered.future;
      final closing = sensor.disconnect();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(busy.writes.map((write) => write.bytes), [start]);
        expect(busy.events, isNot(contains('disconnect:${monitor.id}')));
      } finally {
        busy.releaseRead.complete();
        await read;
        await closing;
      }
      expect(busy.writes.map((write) => write.bytes), [start, stop]);
    },
  );

  for (final replacement in [
    monitor,
    const FoundDevice(id: 'CC:DD', name: 'BOOKOO_EM-2'),
  ]) {
    test(
      'pending stop cannot tear down replacement ${replacement.id}',
      () async {
        final busy = _BusyPressurePlatform()..holdStop = true;
        UniversalBle.setInstance(busy);
        await sensor.pair(monitor);
        final closing = sensor.disconnect();
        await busy.stopEntered.future;
        final reconnecting = sensor.pair(replacement);
        await Future<void>.delayed(Duration.zero);
        final connectionsBeforeStop = busy.events
            .where((event) => event.startsWith('connect:'))
            .length;
        busy.releaseStop.complete();
        await closing;
        await reconnecting;
        expect(sensor.connected, isTrue, reason: busy.events.join('\n'));
        expect(connectionsBeforeStop, 1);
        expect(sensor.name, replacement.name);
        expect(busy.events, [
          'connect:AA:BB',
          'subscribe:AA:BB',
          'start:AA:BB',
          'stop:AA:BB',
          'disconnect:AA:BB',
          'connect:${replacement.id}',
          'subscribe:${replacement.id}',
          'start:${replacement.id}',
        ]);
      },
    );
  }

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
