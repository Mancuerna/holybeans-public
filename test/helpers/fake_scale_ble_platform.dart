import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A peripheral model that answers read queries and the documented buttons.
/// It rejects every setting write and every unsupported button action.
class FakeScaleBlePlatform extends UniversalBlePlatform {
  FakeScaleBlePlatform({this.ti = true, this.alternate = false});

  final bool ti;
  final bool alternate;
  bool respondToStatus = true;
  bool failStatusWrites = false;
  bool failNextControl = false;
  bool resumeFromPause = false;
  int state = 5;
  double grams = 18;
  double flow = 0;
  int seconds = 0;
  int unit = 0;
  int tareCount = 0;
  int tareReadyAfterReads = 0;
  int _tareReadsLeft = 0;
  final events = <String>[];
  final writes = <List<int>>[];
  final subscriptions = <(String, String)>[];
  final _states = <String, BleConnectionState>{};

  String get id => 'DIFLUID-TEST';
  String get name => ti ? 'MB Ti TEST' : 'Microbalance TEST';
  String get service => BleUuidParser.string(ti ? '00DD' : '00EE');
  String get characteristic =>
      BleUuidParser.string(alternate ? 'FF01' : 'AA01');

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
    updateScanResult(BleDevice(deviceId: id, name: name, services: [service]));
    updateScanResult(
      BleDevice(deviceId: 'R2-TEST', name: 'DiFluid R2', services: ['00FF']),
    );
    updateScanResult(BleDevice(deviceId: 'BOOKOO-TEST', name: 'BOOKOO_SC_U'));
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
  ) async => deviceId == 'BOOKOO-TEST'
      ? const []
      : [
          BleService(service, [
            BleCharacteristic(characteristic, [
              CharacteristicProperty.notify,
              CharacteristicProperty.write,
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
    subscriptions.add((service, characteristic));
    events.add('subscribe:$deviceId');
  }

  void _reply(int function, int command, List<int> data) {
    final frame = [0xdf, 0xdf, function, command, data.length, ...data];
    frame.add(frame.fold(0, (sum, b) => sum + b) & 0xff);
    updateCharacteristicValue(
      id,
      characteristic,
      Uint8List.fromList(frame),
      null,
    );
  }

  void publishStatus(int value) {
    state = value;
    _reply(3, 5, [state, 64, 0, 0, 0, 0, 0, 0]);
  }

  /// Feeds a complete weight notification through the actual BLE adapter.
  void emit(double weight, {double flow = 0}) {
    grams = weight;
    this.flow = flow;
    final data = ByteData(13)
      ..setInt32(0, (weight * 10).round())
      ..setInt16(4, (flow * 10).round())
      ..setUint16(6, seconds)
      ..setUint32(8, seconds * 1000)
      ..setUint8(12, unit);
    _reply(3, 0, data.buffer.asUint8List().toList());
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    writes.add(value.toList());
    if (deviceId == 'BOOKOO-TEST') return;
    if (service != this.service || characteristic != this.characteristic) {
      throw StateError('Wrong BLE channel');
    }
    final function = value[2];
    final command = value[3];
    final length = value[4];
    if (function == 1 && command == 4 && length == 0) {
      _reply(1, 4, [unit]);
      return;
    }
    if (function == 3 && command == 5 && length == 0) {
      if (failStatusWrites) throw StateError('Status write failed');
      if (state == 7 && _tareReadsLeft-- <= 0) state = 5;
      if (respondToStatus) _reply(3, 5, [state, 64, 0, 0, 0, 0, 0, 0]);
      return;
    }
    if (function == 3 && command == 0 && length == 0) {
      emit(grams, flow: flow);
      return;
    }
    if (function != 3 || length != 1 || command != 1 && command != 2) {
      throw StateError('Forbidden scale action');
    }
    if (failNextControl) {
      failNextControl = false;
      throw StateError('Write failed');
    }
    if (command == 1 && value[5] == 0) {
      if (state == 10) state = 11;
    } else if (command == 2 && value[5] == 1) {
      if (state == 11) {
        state = 5;
        seconds = 0;
      } else {
        grams = 0;
        tareCount++;
        if (tareReadyAfterReads > 0) {
          state = 7;
          _tareReadsLeft = tareReadyAfterReads;
        }
      }
    } else if (command == 2 && value[5] == 0) {
      state = switch (state) {
        10 => 11,
        11 => resumeFromPause ? 10 : 5,
        _ => 10,
      };
      if (state == 5) seconds = 0;
    } else {
      throw StateError('Unsupported button');
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    events.add('disconnect:$deviceId');
    lose(deviceId);
  }

  void lose(String deviceId) {
    _states[deviceId] = BleConnectionState.disconnected;
    updateConnection(deviceId, false);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected BLE operation: ${invocation.memberName}',
  );
}
