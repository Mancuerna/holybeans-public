import 'dart:async';

import 'package:holybeans/data/services/scale.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_scale_ble_platform.dart';

class MultiScalePlatform extends FakeScaleBlePlatform {
  List<FoundDevice> nearby = [];
  final fail = <String>{};
  Completer<void>? connecting;
  Completer<void>? scanning;
  int scans = 0;
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    scans++;
    await scanning?.future;
    for (final device in nearby) {
      updateScanResult(BleDevice(deviceId: device.id, name: device.name));
    }
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    await connecting?.future;
    if (fail.contains(deviceId)) {
      events.add('failed:$deviceId');
      throw StateError('Unavailable');
    }
    await super.connect(deviceId, connectionTimeout: connectionTimeout);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => [];
}

const ultra = FoundDevice(id: 'ultra', name: 'BOOKOO_SC_U');
const mini = FoundDevice(id: 'mini', name: 'BOOKOO_SC_M');
