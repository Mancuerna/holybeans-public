import 'dart:typed_data';

import 'package:holybeans/domain/niimbot_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

class FakeNiimbotBlePlatform extends UniversalBlePlatform {
  static const service = 'e7810a71-73ae-499d-8c15-faa9aef0c3f2';
  static const characteristic = 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f';
  final decoder = NiimbotDecoder();
  final commands = <NiimbotPacket>[];
  final chunks = <Uint8List>[];
  final events = <String>[];
  int model = 2304;
  int hello = 1;
  int revision = 302;
  bool shortStatus = false;
  bool shortModel = false;
  bool failRows = false;
  int? receivedRow;
  bool validServices = true;
  int? reject;
  int copies = 1;
  bool linked = false;
  int negotiatedMtu = 23;
  bool failMtu = false;

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    events.add('mtu:$expectedMtu');
    if (failMtu) throw UnsupportedError('MTU negotiation unavailable');
    return negotiatedMtu;
  }

  @override
  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {}

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    updateScanResult(BleDevice(deviceId: 'D11-TEST', name: 'D11-TEST'));
    updateScanResult(BleDevice(deviceId: 'D11_H-TEST', name: 'D11_H-TEST'));
    updateScanResult(BleDevice(deviceId: 'D110-TEST', name: 'D110-TEST'));
    updateScanResult(BleDevice(deviceId: 'D110M-TEST', name: 'D110_M-TEST'));
    updateScanResult(BleDevice(deviceId: 'B1-TEST', name: 'B1-TEST'));
    updateScanResult(BleDevice(deviceId: 'B1_PRO-TEST', name: 'B1_PRO-TEST'));
    updateScanResult(BleDevice(deviceId: 'B21-TEST', name: 'B21-TEST'));
    updateScanResult(BleDevice(deviceId: 'B2-TEST', name: 'B2-TEST'));
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    linked = true;
    events.add('connect');
    updateConnection(deviceId, true);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      linked ? BleConnectionState.connected : BleConnectionState.disconnected;
  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => validServices
      ? [
          BleService(service, [
            BleCharacteristic(characteristic, [
              CharacteristicProperty.notify,
              CharacteristicProperty.writeWithoutResponse,
            ], []),
          ]),
        ]
      : [];
  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    events.add('subscribe');
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (bleOutputProperty != BleOutputProperty.withoutResponse) {
      throw StateError('Expected BLE without response');
    }
    chunks.add(value);
    for (final p in decoder.add(value)) {
      commands.add(p);
      events.add('command:${p.command}');
      if (p.command == reject) {
        updateCharacteristicValue(
          deviceId,
          characteristic,
          NiimbotPacket(0xdb, [2]).encode(),
          null,
        );
        continue;
      }
      if (p.command == 0x84 || p.command == 0x85) {
        if (failRows) throw StateError('Simulated row write failure');
        if (receivedRow != null) {
          updateCharacteristicValue(
            deviceId,
            characteristic,
            NiimbotPacket(0xd3, niimbotU16(receivedRow!)).encode(),
            null,
          );
        }
        continue;
      }
      if (p.command == 0x15 ||
          (p.command == 0x01 &&
              (p.payload.length == 7 || p.payload.length == 9))) {
        copies = p.payload[0] * 256 + p.payload[1];
      }
      final reply = switch (p.command) {
        0xa5 => NiimbotPacket(
          0xb5,
          shortStatus
              ? [3, 2]
              : [...List.filled(11, 0), revision ~/ 100, revision % 100],
        ),
        0x86 => NiimbotPacket(0xd3, p.payload.take(2).toList()),
        0xc1 => NiimbotPacket(0xc2, [hello]),
        0x40 => NiimbotPacket(
          0x48,
          shortModel ? [model >> 8] : niimbotU16(model),
        ),
        0x21 => NiimbotPacket(0x31, [2]),
        0x23 => NiimbotPacket(0x33, [1]),
        0x01 => NiimbotPacket(0x02, [1]),
        0x20 => NiimbotPacket(0x30, [1]),
        0x03 => NiimbotPacket(0x04, [1]),
        0x13 => NiimbotPacket(0x14, [1]),
        0x15 => NiimbotPacket(0x16, [1]),
        0xe3 => NiimbotPacket(0xe4, [1]),
        0xa3 => NiimbotPacket(0xb3, [0, copies, 100, 100]),
        0xf3 => NiimbotPacket(0xf4, [1]),
        _ => throw StateError('Unexpected command: ${p.command}'),
      };
      updateCharacteristicValue(deviceId, characteristic, reply.encode(), null);
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    linked = false;
    events.add('disconnect');
    updateConnection(deviceId, false);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
