import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A BOOKOO BLE peripheral that records subscription and transmission order.
class FakePressureBlePlatform extends UniversalBlePlatform {
  final events = <String>[];
  final writes =
      <({String id, String service, String characteristic, List<int> bytes})>[];
  final _states = <String, BleConnectionState>{};
  bool failStart = false;
  bool failStop = false;
  bool loseOnStart = false;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    updateScanResult(
      BleDevice(deviceId: 'BOOKOO-TEST', name: 'BOOKOO_EM-TEST'),
    );
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
    events.add('connect:$deviceId');
    _states[deviceId] = BleConnectionState.connected;
    updateConnection(deviceId, true);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      _states[deviceId] ?? BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => const [];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    events.add('subscribe:$deviceId');
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    writes.add((
      id: deviceId,
      service: service,
      characteristic: characteristic,
      bytes: value.toList(),
    ));
    final starting = value[2] == 1;
    events.add('${starting ? 'start' : 'stop'}:$deviceId');
    if (starting ? failStart : failStop) {
      throw StateError('Transmission failed');
    }
    if (starting && loseOnStart) lose(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    events.add('disconnect:$deviceId');
    _states[deviceId] = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  /// Reports the loss of the peripheral without an app command.
  void lose(String deviceId) {
    _states[deviceId] = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected BLE operation: ${invocation.memberName}',
  );
}
