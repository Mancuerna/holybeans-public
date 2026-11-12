import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pm240_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

import 'fake_marklife_ble_platform.dart';

class PmPrintPlatform extends FakeMarklifeBlePlatform {
  List<int>? reply = [0];
  int queries = 0;
  int? failStatusAfterQuery;
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    for (final name in [
      'PM240_TEST',
      'PM240C',
      'P15_TEST',
      'FICHERO_5836',
      'PM2400',
    ]) {
      updateScanResult(BleDevice(deviceId: name, name: name));
    }
  }

  Completer<void>? gate;
  Completer<void>? writeGate;
  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    await gate?.future;
    await super.connect(deviceId, connectionTimeout: connectionTimeout);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    events.add('subscribe:$characteristic');
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    expect(service, Pm240Protocol.service);
    expect(characteristic, Pm240Protocol.tx);
    expect(bleOutputProperty, BleOutputProperty.withoutResponse);
    expect(value.length, lessThanOrEqualTo(20));
    chunks.add(Uint8List.fromList(value));
    if (chunks.length == failAtChunk) throw StateError('private-address');
    if (value.join(',') == Pm240Protocol.statusQuery.join(',')) {
      queries++;
      if (reply != null) {
        updateCharacteristicValue(
          deviceId,
          Pm240Protocol.responses.last,
          Uint8List.fromList(
            failStatusAfterQuery != null && queries > failStatusAfterQuery!
                ? [4]
                : reply!,
          ),
          null,
        );
      }
    } else {
      await writeGate?.future;
    }
  }
}
