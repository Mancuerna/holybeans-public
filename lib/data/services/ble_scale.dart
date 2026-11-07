import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/acaia_scale_connection.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/difluid_scale_connection.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/data/services/scale_discovery.dart';
import 'package:holybeans/data/services/timemore_dot_connection.dart';
import 'package:holybeans/domain/acaia_protocol.dart';
import 'package:holybeans/domain/bookoo_protocol.dart';
import 'package:holybeans/domain/difluid_scale_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// Bluetooth scales exposing the same readings and brew commands.
class BleScale extends BleLink<ScaleReading> implements Scale {
  BleScale(this.settings, {super.trace, ScaleDiscovery? discovery})
    : _discovery = discovery ?? ScaleDiscovery();

  final ScaleDiscovery _discovery;
  List<FoundDevice> _scales = const [];

  @override
  List<FoundDevice> get rememberedScales => List.unmodifiable(_scales);

  @override
  String? get activeScaleId => connectedId;

  @override
  Future<List<FoundDevice>> reconnectCandidates(FoundDevice preferred) =>
      _scales.length < 2
      ? super.reconnectCandidates(preferred)
      : _discovery.nearby(_scales);

  @override
  void cancelReconnect() => _discovery.cancel();

  @override
  Future<void> forgetScale(String id) async {
    if (id == activeScaleId || !connected) await disconnect();
    await settings.forget(id);
    await _loadScales();
    setRemembered(_scales.firstOrNull);
  }

  Future<void> _loadScales() async {
    _scales = [
      for (final s in await settings.loadAll())
        FoundDevice(id: s.deviceId, name: s.name),
    ];
  }

  final ScaleSettings settings;
  final _doses = StreamController<double>.broadcast();

  @override
  Stream<double> get doses => _doses.stream;

  DifluidScaleConnection? _difluid;
  AcaiaScaleConnection? _acaia;
  TimemoreDotConnection? _dot;
  Future<bool> _commands = Future.value(true);
  int _generation = 0;
  bool _bookooDoseNotify = false;
  StreamSubscription<Uint8List>? _bookooDoseNotifications;

  @override
  String get service => _dot != null
      ? DotUuids.service
      : _acaia?.service ?? _difluid?.service ?? BookooUuids.service;

  @override
  String get characteristic => _dot != null
      ? DotUuids.notify
      : _acaia?.notify ?? _difluid?.characteristic ?? BookooUuids.weight;

  @override
  bool matchesName(String? name) =>
      isBookooScaleName(name) ||
      isDifluidScaleName(name) ||
      isAcaiaScaleName(name) ||
      isTimemoreDotName(name);

  static bool _advertises(BleDevice device, String service) => device.services
      .any((uuid) => BleUuidParser.stringOrNull(uuid) == service);

  @override
  bool matchesAdvertisement(BleDevice device) =>
      matchesName(device.name) ||
      _advertises(device, DifluidScaleUuids.microbalance) ||
      _advertises(device, DifluidScaleUuids.microbalanceTi) ||
      (device.name?.trim().isNotEmpty != true &&
          _advertises(device, DotUuids.service));

  @override
  String advertisedName(BleDevice device) => device.name?.isNotEmpty == true
      ? device.name!
      : _advertises(device, DotUuids.service)
      ? 'Timemore DOT?'
      : _advertises(device, DifluidScaleUuids.microbalanceTi)
      ? 'DiFluid Microbalance Ti'
      : 'DiFluid Microbalance';

  @override
  void configureServices(FoundDevice device, List<BleService> services) {
    _difluid = null;
    _acaia = null;
    _dot = null;
    _bookooDoseNotify = false;
    if (isAcaiaScaleName(device.name)) {
      for (final found in services) {
        for (final classic in [false, true]) {
          final notifyId = classic ? AcaiaUuids.classic : AcaiaUuids.notify;
          final writeId = classic ? AcaiaUuids.classic : AcaiaUuids.write;
          final notify = found.characteristics
              .where((c) => c.uuid == notifyId)
              .firstOrNull;
          final write = found.characteristics
              .where((c) => c.uuid == writeId)
              .firstOrNull;
          if (notify == null ||
              write == null ||
              !notify.properties.contains(CharacteristicProperty.notify) ||
              !write.properties.any(
                (p) =>
                    p == CharacteristicProperty.write ||
                    p == CharacteristicProperty.writeWithoutResponse,
              )) {
            continue;
          }
          _acaia = AcaiaScaleConnection(
            id: device.id,
            service: found.uuid,
            notify: notifyId,
            write: writeId,
            classic: classic,
            withResponse: write.properties.contains(
              CharacteristicProperty.write,
            ),
            supportsWriteWithoutResponse: write.properties.contains(
              CharacteristicProperty.writeWithoutResponse,
            ),
            trace: trace,
          );
          return;
        }
      }
      throw StateError('No supported Acaia channel');
    }
    if (isBookooScaleName(device.name)) {
      _bookooDoseNotify = services
          .where((service) => service.uuid == BookooUuids.service)
          .expand((service) => service.characteristics)
          .any(
            (c) =>
                c.uuid == BookooUuids.command &&
                c.properties.contains(CharacteristicProperty.notify),
          );
      return;
    }
    if (isTimemoreDotName(device.name)) {
      final channel = services
          .where((s) => s.uuid == DotUuids.service)
          .firstOrNull;
      final notify = channel?.characteristics
          .where((c) => c.uuid == DotUuids.notify)
          .firstOrNull;
      final write = channel?.characteristics
          .where((c) => c.uuid == DotUuids.write)
          .firstOrNull;
      if (notify == null ||
          !notify.properties.contains(CharacteristicProperty.notify) ||
          write == null ||
          !write.properties.any(
            (p) =>
                p == CharacteristicProperty.write ||
                p == CharacteristicProperty.writeWithoutResponse,
          )) {
        throw StateError('Missing Dot notification/write channel');
      }
      _dot = TimemoreDotConnection(
        id: device.id,
        withResponse: !write.properties.contains(
          CharacteristicProperty.writeWithoutResponse,
        ),
        trace: trace,
      );
      return;
    }
    for (final uuid in [
      DifluidScaleUuids.microbalanceTi,
      DifluidScaleUuids.microbalance,
    ]) {
      for (final found in services.where((service) => service.uuid == uuid)) {
        // AA01 is the maker's cleartext channel and the one used by BQ.
        // Some Microbalance firmware exposes only FF01; verify its replies
        // before any tare or timer command can be sent.
        for (final channel in [
          DifluidScaleUuids.cleartext,
          if (uuid == DifluidScaleUuids.microbalance)
            DifluidScaleUuids.alternate,
        ]) {
          if (found.characteristics.any((c) => c.uuid == channel)) {
            _difluid = DifluidScaleConnection(
              id: device.id,
              service: uuid,
              characteristic: channel,
              trace: trace,
            );
            return;
          }
        }
      }
    }
    throw StateError('No supported scale service');
  }

  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    if (_bookooDoseNotify) {
      _bookooDoseNotifications =
          UniversalBle.characteristicValueStream(
            deviceId,
            BookooUuids.command,
          ).listen(
            _receiveBookooDose,
            onError: (Object error) =>
                traceEvent('scale.dose.error', {'error': '$error'}),
          );
      try {
        await UniversalBle.subscribeNotifications(
          deviceId,
          BookooUuids.service,
          BookooUuids.command,
        );
      } on Object catch (error) {
        // The optional dose channel must not prevent live weighing.
        await _bookooDoseNotifications?.cancel();
        _bookooDoseNotifications = null;
        traceEvent('scale.dose.subscribe.error', {'error': '$error'});
      }
    }
    await _difluid?.start();
    await _acaia?.start();
    await _dot?.start();
  }

  @override
  void connectionClosed() {
    _generation++;
    unawaited(_bookooDoseNotifications?.cancel());
    _bookooDoseNotifications = null;
    _bookooDoseNotify = false;
    _dot?.close();
    _dot = null;
    _acaia?.close();
    _acaia = null;
    _difluid?.close();
    _difluid = null;
  }

  @override
  Iterable<ScaleReading> parseReadings(Uint8List packet) =>
      _dot?.parse(packet) ??
      _acaia?.parse(packet) ??
      super.parseReadings(packet);

  @override
  ScaleReading? parse(Uint8List packet) {
    if (_dot case final dot?) return dot.parse(packet).lastOrNull;
    if (_acaia case final acaia?) return acaia.parse(packet).lastOrNull;
    if (_difluid == null) {
      if (_receiveBookooDose(packet)) return null;
    }
    final reading =
        _difluid?.parse(packet) ??
        (_difluid == null ? parseBookooWeight(packet) : null);
    if (reading != null && trace != null) {
      traceEvent('scale.reading', {
        'grams': reading.grams,
        'flow': reading.flowGramsPerSecond,
        'timerMs': reading.timerMs,
        'timerRunning': reading.timerRunning,
        'timerAutoStopped': reading.timerAutoStopped,
        'battery': reading.batteryPercent,
      });
    }
    return reading;
  }

  bool _receiveBookooDose(Uint8List packet) {
    final dose = parseBookooDose(packet);
    if (dose == null) return false;
    traceEvent('scale.dose', {'grams': dose});
    _doses.add(dose);
    return true;
  }

  @override
  Future<FoundDevice?> loadRemembered() async {
    await _loadScales();
    return _scales.firstOrNull;
  }

  @override
  Future<void> saveRemembered(FoundDevice? device) async {
    await settings.save(
      device == null
          ? null
          : RememberedScale(deviceId: device.id, name: device.name),
    );
    await _loadScales();
  }

  @override
  ScaleReading? get reading => latest;

  @override
  void dispose() {
    unawaited(_doses.close());
    super.dispose();
  }

  @override
  Future<bool> send(ScaleCommand command) {
    final id = connectedId;
    final generation = _generation;
    final difluid = _difluid;
    final acaia = _acaia;
    final dot = _dot;
    if (id == null) return Future.value(false);
    return _commands = _commands.then((_) async {
      if (connectedId != id || generation != _generation) return false;
      if (dot != null) return dot.send(command);
      if (acaia != null) return acaia.send(command);
      if (difluid != null) return difluid.send(command);
      try {
        await UniversalBle.write(
          id,
          BookooUuids.service,
          BookooUuids.command,
          Uint8List.fromList(bookooCommandBytes(command)),
        );
        return true;
      } on Object {
        return false;
      }
    });
  }
}
