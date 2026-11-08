import 'dart:typed_data';

import 'package:holybeans/domain/marklife_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_niimbot_ble_platform.dart';

class FakeMarklifeBlePlatform extends FakeNiimbotBlePlatform {
  bool hasControl = true;
  int? failAtChunk;
  final received = <int>[];
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    for (final name in ['P12_TEST_BLE', 'P15_TEST', 'D110_TEST', 'P120_TEST']) {
      updateScanResult(BleDevice(deviceId: name, name: name));
    }
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => [
    BleService(MarklifeProtocol.service, [
      BleCharacteristic(MarklifeProtocol.rx, [
        CharacteristicProperty.notify,
      ], []),
      BleCharacteristic(MarklifeProtocol.tx, [
        CharacteristicProperty.writeWithoutResponse,
      ], []),
      if (hasControl)
        BleCharacteristic(MarklifeProtocol.control, [
          CharacteristicProperty.notify,
        ], []),
    ]),
  ];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    events.add('subscribe:$characteristic');
    if (characteristic == MarklifeProtocol.control) {
      updateCharacteristicValue(
        deviceId,
        characteristic,
        Uint8List.fromList([1, 4]),
        null,
      );
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (service != MarklifeProtocol.service ||
        characteristic != MarklifeProtocol.tx ||
        bleOutputProperty != BleOutputProperty.withoutResponse) {
      throw StateError('Wrong P12 transport');
    }
    chunks.add(Uint8List.fromList(value));
    if (chunks.length == failAtChunk) throw StateError('Link lost');
    received.addAll(value);
    updateCharacteristicValue(
      deviceId,
      MarklifeProtocol.control,
      Uint8List.fromList([1, 1]),
      null,
    );
    if (received.length >= 4 &&
        received.sublist(received.length - 4).join(',') == '16,255,241,69') {
      updateCharacteristicValue(
        deviceId,
        MarklifeProtocol.rx,
        Uint8List.fromList([0xaa]),
        null,
      );
    }
  }
}
