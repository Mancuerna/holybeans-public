import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/multi_scale_ble_platform.dart';

void main() {
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
