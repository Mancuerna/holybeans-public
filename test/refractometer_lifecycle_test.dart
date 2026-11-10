import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/domain/difluid_r2_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_scale_ble_platform.dart';

void main() {
  late _R2Platform platform;
  late BleRefractometer device;
  setUp(() async {
    platform = _R2Platform();
    UniversalBle.setInstance(platform);
    device = BleRefractometer(_MemoryPair());
    await device.pair(FoundDevice(id: platform.id, name: 'R2 Test'));
  });
  tearDown(() async {
    await device.disconnect();
    device.dispose();
  });

  test('a lost measurement does not block measuring after reconnect', () async {
    platform.emitFrame(difluidFrame(3, 0, [0, 11]));
    await Future<void>.delayed(Duration.zero);
    expect(device.measuring, isTrue);
    platform.lose(platform.id);
    await Future<void>.delayed(Duration.zero);
    await device.connect();
    expect(device.measuring, isFalse);
    expect(await device.measure(), isTrue);
    expect(platform.measurements, 1);
  });

  test(
    'losing the link while reading the test count sends no later measure',
    () async {
      platform.respond = false;
      final pending = device.measure();
      await platform.queried.future;
      platform.lose(platform.id);
      await Future<void>.delayed(Duration.zero);
      expect(await pending, isFalse);
      expect(platform.measurements, 0);
    },
  );
}

class _MemoryPair extends PairedDeviceFile {
  _MemoryPair() : super(File('unused-r2-test'));
  FoundDevice? device;
  @override
  Future<FoundDevice?> load() async => device;
  @override
  Future<void> save(FoundDevice? value) async => device = value;
}

class _R2Platform extends FakeScaleBlePlatform {
  bool respond = true;
  int measurements = 0;
  final queried = Completer<void>();
  @override
  String get id => 'R2-TEST';
  @override
  String get service => DifluidR2Uuids.service;
  @override
  String get characteristic => DifluidR2Uuids.characteristic;
  void emitFrame(List<int> frame) => updateCharacteristicValue(
    id,
    characteristic,
    Uint8List.fromList(frame),
    null,
  );
  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (value[2] == 1 && value[3] == 3) {
      if (!queried.isCompleted) queried.complete();
      if (respond) emitFrame(difluidFrame(1, 3, [1]));
    } else if (value[2] == 3 && value[3] == 0) {
      measurements++;
    } else {
      throw StateError('Unsupported R2 write');
    }
  }
}
