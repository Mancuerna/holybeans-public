import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/multi_scale_ble_platform.dart';

void main() {
  test('a silent native connection times out and can be retried', () async {
    final platform = _SilentPlatform();
    UniversalBle.setInstance(platform);
    final link = _Link()..remembered = mini;
    await link.load();
    final pending = link.connect();
    await Future<void>.delayed(Duration.zero);
    expect(link.status, DeviceStatus.connecting);
    await pending;
    expect(link.status, DeviceStatus.failed);
    expect(platform.events, contains('disconnect:mini'));
    platform.silent = false;
    await link.connect();
    expect(link.currentId, mini.id);
    await link.disconnect();
    link.dispose();
  });

  for (final stage in ['discovery', 'subscription', 'handshake']) {
    for (final fail in [false, true]) {
      test(
        'link loss during $stage releases reconnect, late fail=$fail',
        () async {
          final platform = _SetupPlatform(stage);
          UniversalBle.setInstance(platform);
          final link = _Link(
            handshake: stage == 'handshake' ? platform.release : null,
            entered: stage == 'handshake' ? platform.entered : null,
          )..remembered = mini;
          await link.load();
          final pending = link.connect();
          try {
            await platform.entered.future;
            platform.lose(mini.id);
            await Future<void>.delayed(Duration.zero);
            expect(link.status, DeviceStatus.idle);
            expect(link.currentId, isNull);

            void finishSetup() {
              if (fail) {
                platform.release.completeError(StateError('Old setup failed'));
              } else {
                platform.release.complete();
              }
            }

            // Native GATT operations share a queue. Let them finish, but keep
            // the application handshake pending while starting its replacement.
            if (stage != 'handshake') {
              finishSetup();
              await pending;
              expect(link.connected, isFalse);
            }
            await link.connect();
            expect(link.connected, isTrue);
            final disconnects = platform.events
                .where((event) => event == 'disconnect:${mini.id}')
                .length;
            if (stage == 'handshake') finishSetup();
            await pending;
            expect(link.currentId, mini.id);
            expect(
              platform.events.where(
                (event) => event == 'disconnect:${mini.id}',
              ),
              hasLength(disconnects),
            );
          } finally {
            if (!platform.release.isCompleted) platform.release.complete();
            await pending;
            await link.disconnect();
            link.dispose();
          }
        },
      );
    }
  }

  for (final action in ['disconnect', 'search', 'pair', 'dispose']) {
    test(
      '$action interrupts a pending native connection immediately',
      () async {
        final platform = _HeldPlatform()..nearby = [ultra];
        UniversalBle.setInstance(platform);
        final link = _Link()..remembered = mini;
        await link.load();
        final pending = link.connect(automatic: true);
        var disposed = false;
        try {
          await platform.started.future;
          switch (action) {
            case 'dispose':
              link.dispose();
              disposed = true;
              await Future<void>.delayed(Duration.zero);
            case 'disconnect':
              await link.disconnect();
            case 'search':
              await link.search();
            case 'pair':
              await link.pair(ultra);
          }
          expect(platform.events, contains('disconnect:mini'));
          await pending.timeout(const Duration(seconds: 1));
          if (action == 'search') {
            expect(link.status, DeviceStatus.searching);
            expect(link.found.map((d) => d.id), contains(ultra.id));
          } else if (action == 'pair') {
            expect(link.currentId, ultra.id);
            expect(link.remembered, ultra);
          } else if (action == 'dispose') {
            expect(link.connected, isFalse);
          } else {
            expect(link.status, DeviceStatus.idle);
            await link.connect(automatic: true);
            expect(link.connected, isFalse);
          }
        } finally {
          platform.release.complete();
          await pending;
          if (!disposed) {
            await link.stopSearch();
            await link.disconnect();
            link.dispose();
          }
        }
      },
    );
  }

  for (final fail in [false, true]) {
    for (final replacement in [mini, ultra]) {
      test(
        'late handshake fail=$fail preserves replacement ${replacement.id}',
        () async {
          final platform = MultiScalePlatform();
          UniversalBle.setInstance(platform);
          final handshake = Completer<void>();
          final entered = Completer<void>();
          final link = _Link(handshake: handshake, entered: entered);
          final old = link.pair(mini);
          try {
            await entered.future;
            await link.pair(replacement);
            expect(link.currentId, replacement.id);
            int disconnects() => platform.events
                .where((e) => e == 'disconnect:${replacement.id}')
                .length;
            final before = disconnects();
            if (fail) {
              handshake.completeError(StateError('Old handshake failed'));
            } else {
              handshake.complete();
            }
            await old;
            expect(link.currentId, replacement.id);
            expect(link.remembered, replacement);
            expect(disconnects(), before);
          } finally {
            if (!handshake.isCompleted) handshake.complete();
            await old;
            await link.disconnect();
            link.dispose();
          }
        },
      );
    }
  }
}

class _SilentPlatform extends MultiScalePlatform {
  bool silent = true;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    if (silent) return;
    await super.connect(deviceId, connectionTimeout: connectionTimeout);
  }
}

class _SetupPlatform extends MultiScalePlatform {
  _SetupPlatform(this.stage);

  final String stage;
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> _hold(String current) async {
    if (stage != current || entered.isCompleted) return;
    entered.complete();
    await release.future;
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    await _hold('discovery');
    return super.discoverServices(deviceId, withDescriptors);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await _hold('subscription');
    await super.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
  }
}

class _HeldPlatform extends MultiScalePlatform {
  final started = Completer<void>();
  final release = Completer<void>();
  bool cancelled = false;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    if (deviceId == mini.id) {
      started.complete();
      await release.future;
      if (cancelled) return;
    }
    await super.connect(deviceId, connectionTimeout: connectionTimeout);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    if (deviceId == mini.id) cancelled = true;
    await super.disconnect(deviceId);
  }
}

class _Link extends BleLink<int> {
  _Link({this.handshake, this.entered});
  final Completer<void>? handshake;
  final Completer<void>? entered;
  FoundDevice? remembered;
  bool _holdHandshake = true;
  String? get currentId => connectedId;
  @override
  String get service => BleUuidParser.string('00DD');
  @override
  String get characteristic => BleUuidParser.string('AA01');
  @override
  bool matchesName(String? name) => true;
  @override
  int? parse(Uint8List packet) => null;
  @override
  Future<FoundDevice?> loadRemembered() async => remembered;
  @override
  Future<void> saveRemembered(FoundDevice? device) async => remembered = device;
  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    if (deviceId == mini.id && handshake != null && _holdHandshake) {
      _holdHandshake = false;
      entered!.complete();
      await handshake!.future;
    }
  }
}
