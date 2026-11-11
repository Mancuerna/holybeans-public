import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/data/services/scale_discovery.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/multi_scale_ble_platform.dart';
import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late MultiScalePlatform platform;
  late BleScale scale;
  setUp(() async {
    database = memoryDatabase();
    platform = MultiScalePlatform();
    UniversalBle.setInstance(platform);
    scale = BleScale(
      ScaleSettings(database),
      discovery: ScaleDiscovery(duration: const Duration(milliseconds: 30)),
    );
    await scale.pair(ultra);
    await scale.pair(mini);
    platform.lose(mini.id);
    await Future<void>.delayed(Duration.zero);
    platform.events.clear();
  });
  tearDown(() async {
    await scale.disconnect();
    scale.dispose();
    await database.close();
  });
  test('connects to the available known scale and remembers the choice across restart', () async {
    platform.nearby = [
      ultra,
      const FoundDevice(id: 'stranger', name: 'BOOKOO_SC_U'),
    ];
    await scale.connect(automatic: true);
    expect(scale.activeScaleId, ultra.id);
    expect(platform.events.where((e) => e.startsWith('connect:')), [
      'connect:ultra',
    ]);
    expect((await scale.settings.loadAll()).map((s) => s.deviceId), [
      'ultra',
      'mini',
    ]);
    final settings = scale.settings;
    await scale.disconnect();
    scale.dispose();
    scale = BleScale(
      settings,
      discovery: ScaleDiscovery(duration: const Duration(milliseconds: 30)),
    );
    await scale.load();
    platform.nearby = [mini];
    await scale.connect(automatic: true);
    expect(scale.activeScaleId, mini.id);
  });
  test(
    'prefers the last used scale regardless of advertisement order',
    () async {
      platform.nearby = [ultra, mini];
      await scale.connect(automatic: true);
      expect(scale.activeScaleId, mini.id);
      platform.nearby = [ultra];
      await scale.connect(automatic: true);
      expect(scale.activeScaleId, mini.id);
      expect(platform.scans, 1);
    },
  );
  test(
    'falls back when the preferred advertised scale cannot connect',
    () async {
      platform.nearby = [mini, ultra];
      platform.fail.add(mini.id);
      await scale.connect(automatic: true);
      expect(scale.activeScaleId, ultra.id);
    },
  );
  test('ignores strangers and retries after a scale is switched on', () async {
    platform.nearby = [const FoundDevice(id: 'other', name: 'BOOKOO_SC_U')];
    await scale.connect(automatic: true);
    expect(scale.connected, isFalse);
    expect(platform.events, isEmpty);
    platform.nearby = [ultra];
    await scale.connect(automatic: true);
    expect(scale.activeScaleId, ultra.id);
    expect(platform.writes, isEmpty);
  });
  test(
    'disconnect cancels discovery and holds off later automatic attempts',
    () async {
      platform.scanning = Completer<void>();
      final pending = scale.connect(automatic: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await scale.disconnect();
      platform.nearby = [mini, ultra];
      platform.scanning!.complete();
      await pending;
      await scale.connect(automatic: true);
      expect(scale.connected, isFalse);
      expect(platform.events, isEmpty);
      await scale.connect();
      expect(scale.activeScaleId, mini.id);
    },
  );
  test(
    'disconnect cancels a native connection in flight without remembering it',
    () async {
      platform.nearby = [ultra, mini];
      platform.connecting = Completer<void>();
      final pending = scale.connect(automatic: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await scale.disconnect();
      platform.connecting!.complete();
      await pending;
      expect(scale.connected, isFalse);
      expect(scale.status, DeviceStatus.idle);
      expect(platform.events.last, 'disconnect:mini');
    },
  );
  test(
    'forgetting an inactive scale keeps automatic reconnection enabled',
    () async {
      await scale.forgetScale(ultra.id);
      await scale.connect(automatic: true);
      expect(scale.activeScaleId, mini.id);
      expect(scale.rememberedScales.map((s) => s.id), ['mini']);
    },
  );
  test('concurrent retries start only one scan and one connection', () async {
    platform.nearby = [ultra, mini];
    await Future.wait([
      scale.connect(automatic: true),
      scale.connect(automatic: true),
    ]);
    expect(platform.scans, 1);
    expect(platform.events.where((e) => e.startsWith('connect:')), [
      'connect:mini',
    ]);
  });
  test(
    'forgetting one scale keeps the other connection and persists removal',
    () async {
      platform.nearby = [ultra, mini];
      await scale.connect(automatic: true);
      await scale.forgetScale(ultra.id);
      expect(scale.activeScaleId, mini.id);
      expect(scale.rememberedScales.map((s) => s.id), ['mini']);
      expect((await scale.settings.loadAll()).map((s) => s.deviceId), ['mini']);
      await scale.forgetScale(mini.id);
      expect(scale.rememberedScales, isEmpty);
      expect(scale.connected, isFalse);
    },
  );
}
