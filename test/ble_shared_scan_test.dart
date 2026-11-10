import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/scale_discovery.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_scale_ble_platform.dart';

void main() {
  late _ScanPlatform platform;
  late _Link first;
  late _Link second;
  var disposedFirst = false;
  setUp(() {
    platform = _ScanPlatform();
    UniversalBle.setInstance(platform);
    first = _Link();
    second = _Link();
    disposedFirst = false;
  });
  tearDown(() async {
    if (!disposedFirst) {
      await first.stopSearch();
      first.dispose();
    }
    await second.stopSearch();
    second.dispose();
  });

  test('stopping one search keeps the other native scan alive', () async {
    await first.search();
    await second.search();
    expect(platform.starts, 1);
    await first.stopSearch();
    expect(platform.stops, 0);
    platform.publish();
    await Future<void>.delayed(Duration.zero);
    expect(second.found.map((d) => d.id), ['known']);
    await second.stopSearch();
    expect(platform.stops, 1);
  });

  test('concurrent searches on one link acquire only one scan use', () async {
    await Future.wait([first.search(), first.search()]);
    expect(platform.starts, 1);
    await first.stopSearch();
    expect(platform.stops, 1);
  });

  test('disposing one search releases only its own scan use', () async {
    await first.search();
    await second.search();
    first.dispose();
    disposedFirst = true;
    await Future<void>.delayed(Duration.zero);
    expect(platform.stops, 0);
    await second.stopSearch();
    expect(platform.stops, 1);
  });

  test('known-scale discovery shares a running interactive search', () async {
    await first.search();
    final discovery = ScaleDiscovery(duration: const Duration(seconds: 1));
    final nearby = discovery.nearby([
      const FoundDevice(id: 'known', name: 'Known'),
    ]);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(platform.starts, 1);
      platform.publish();
      expect((await nearby).single.id, 'known');
      expect(platform.stops, 0);
    } finally {
      discovery.cancel();
      await nearby;
    }
  });

  test('failed shared startup releases all uses and can be retried', () async {
    platform.fail = true;
    await Future.wait([first.search(), second.search()]);
    expect(first.status, DeviceStatus.failed);
    expect(second.status, DeviceStatus.failed);
    expect(platform.starts, 1);
    expect(platform.stops, 1);
    platform.fail = false;
    await first.search();
    expect(first.status, DeviceStatus.searching);
    expect(platform.starts, 2);
  });

  test('stopping during startup leaves no active scan', () async {
    platform.startGate = Completer<void>();
    final search = first.search();
    await platform.started.future;
    final stopped = first.stopSearch();
    platform.startGate!.complete();
    await Future.wait([search, stopped]);
    expect(first.status, DeviceStatus.idle);
    expect(platform.stops, 1);
    expect(platform.running, isFalse);
  });
}

class _ScanPlatform extends FakeScaleBlePlatform {
  int starts = 0;
  int stops = 0;
  bool fail = false;
  bool running = false;
  Completer<void>? startGate;
  final started = Completer<void>();
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    starts++;
    if (!started.isCompleted) started.complete();
    await startGate?.future;
    if (fail) throw StateError('Cannot scan');
    running = true;
  }

  @override
  Future<void> stopScan() async {
    stops++;
    running = false;
  }

  void publish() {
    if (running) updateScanResult(BleDevice(deviceId: 'known', name: 'Known'));
  }
}

class _Link extends BleLink<int> {
  @override
  String get service => BleUuidParser.string('00DD');
  @override
  String get characteristic => BleUuidParser.string('AA01');
  @override
  bool matchesName(String? name) => true;
  @override
  int? parse(Uint8List packet) => null;
  @override
  Future<FoundDevice?> loadRemembered() async => null;
  @override
  Future<void> saveRemembered(FoundDevice? device) async {}
}
