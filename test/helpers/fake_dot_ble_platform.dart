import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/data/services/timemore_dot_connection.dart';
import 'package:holybeans/domain/timemore_dot_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_scale_ble_platform.dart';

Uint8List dotReply(int operation, int command, List<int> payload) {
  final raw = [0xa5, 0x5a, operation, command, 0, payload.length, ...payload];
  final crc = dotCrc(raw);
  return Uint8List.fromList([...raw, crc >> 8, crc & 255]);
}

Uint8List dotWeight(
  int tenths, {
  int flow = 0,
  int seconds = 0,
  int overload = 0,
}) {
  final data = ByteData(9)
    ..setInt32(0, tenths)
    ..setInt16(4, flow)
    ..setUint16(6, seconds)
    ..setUint8(8, overload);
  return dotReply(1, 1, data.buffer.asUint8List());
}

class FakeDotBlePlatform extends FakeScaleBlePlatform {
  @override
  String get id => 'DOT-TEST';
  @override
  String get name => 'TIMEMORE DOT';
  @override
  String get service => DotUuids.service;
  @override
  String get characteristic => DotUuids.notify;
  String model = 'TES017';
  String maker = 'TIMEMORE';
  String? firmware = 'v1.0.4';
  bool reservedZeroCrc = false;
  bool bonded = false;
  bool bondSucceeds = true;
  bool acknowledge = true;
  bool acceptCommand = true;
  bool answerQueries = true;
  bool writeWithResponseOnly = false;
  bool failWrite = false;
  bool applyReset = true;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    updateScanResult(BleDevice(deviceId: id, name: null, services: [service]));
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => [
    BleService(service, [
      BleCharacteristic(characteristic, [CharacteristicProperty.notify], []),
      BleCharacteristic(DotUuids.write, [
        writeWithResponseOnly
            ? CharacteristicProperty.write
            : CharacteristicProperty.writeWithoutResponse,
      ], []),
    ]),
    BleService(DotUuids.info, [
      for (final uuid in [DotUuids.model, DotUuids.maker, DotUuids.firmware])
        BleCharacteristic(uuid, [CharacteristicProperty.read], []),
    ]),
  ];

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async {
    events.add('read:$characteristic');
    if (service != DotUuids.info) throw StateError('Unexpected read');
    final value = characteristic == DotUuids.model
        ? model
        : characteristic == DotUuids.maker
        ? maker
        : firmware;
    if (value == null) throw StateError('Firmware unavailable');
    return Uint8List.fromList(utf8.encode(value));
  }

  @override
  Future<bool> isPaired(String deviceId) async => bonded;

  @override
  Future<bool> pair(String deviceId) async {
    events.add('bond');
    return bonded = bondSucceeds;
  }

  void publish(Uint8List bytes) {
    final packet = Uint8List.fromList(bytes);
    if (reservedZeroCrc) {
      packet[packet.length - 2] = 0;
      packet[packet.length - 1] = 0;
    }
    updateCharacteristicValue(id, characteristic, packet, null);
  }

  @override
  void emit(double weight, {double flow = 0}) {
    grams = weight;
    publish(
      dotWeight(
        (weight * 10).round(),
        flow: (flow * 10).round(),
        seconds: seconds,
      ),
    );
  }

  void completeReset() {
    seconds = 0;
    state = 5;
    emit(grams);
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    if (service != this.service ||
        characteristic != DotUuids.write ||
        !bonded) {
      throw StateError('Wrong channel or unbonded');
    }
    if (bleOutputProperty !=
        (writeWithResponseOnly
            ? BleOutputProperty.withResponse
            : BleOutputProperty.withoutResponse)) {
      throw StateError('Wrong write mode');
    }
    writes.add(value.toList());
    events.add('write:${value[2]}:${value[3]}');
    if (failWrite) throw StateError('Simulated GATT error');
    if (value[2] == 2 && value[5] == 0 && [2, 5, 6].contains(value[3])) {
      if (!answerQueries) return;
      publish(
        dotReply(2, value[3], switch (value[3]) {
          2 => [state == 10 ? 1 : (state == 11 ? 2 : 3)],
          5 => [2, 76],
          _ => [unit],
        }),
      );
      return;
    }
    if (value[2] != 3 ||
        !(value[3] == 13 && value[5] == 0 ||
            value[3] == 2 && value[5] == 1 && [1, 2, 3].contains(value[6]))) {
      throw StateError('Forbidden Dot command');
    }
    if (!acknowledge) return;
    publish(dotReply(3, value[3], [acceptCommand ? 1 : 0]));
    if (!acceptCommand) return;
    if (value[3] == 13) {
      tareCount++;
      emit(0);
    } else if (value[6] == 3) {
      if (applyReset) completeReset();
    } else {
      state = value[6] == 1 ? 10 : 11;
    }
  }
}
