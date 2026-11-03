import 'package:flutter/foundation.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/acaia_scale_connection.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/difluid_scale_connection.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/data/services/scale_discovery.dart';
import 'package:holybeans/domain/acaia_protocol.dart';
import 'package:holybeans/domain/bookoo_protocol.dart';
import 'package:holybeans/domain/difluid_scale_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

/// BOOKOO, DiFluid and Acaia scales, exposing the same readings and brew commands.
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
  DifluidScaleConnection? _difluid;
  AcaiaScaleConnection? _acaia;
  Future<bool> _commands = Future.value(true);
  int _generation = 0;

  @override
  String get service =>
      _acaia?.service ?? _difluid?.service ?? BookooUuids.service;

  @override
  String get characteristic =>
      _acaia?.notify ?? _difluid?.characteristic ?? BookooUuids.weight;

  @override
  bool matchesName(String? name) =>
      isBookooScaleName(name) ||
      isDifluidScaleName(name) ||
      isAcaiaScaleName(name);

  static bool _advertises(BleDevice device, String service) => device.services
      .any((uuid) => BleUuidParser.stringOrNull(uuid) == service);

  @override
  bool matchesAdvertisement(BleDevice device) =>
      matchesName(device.name) ||
      _advertises(device, DifluidScaleUuids.microbalance) ||
      _advertises(device, DifluidScaleUuids.microbalanceTi);

  @override
  String advertisedName(BleDevice device) => device.name?.isNotEmpty == true
      ? device.name!
      : _advertises(device, DifluidScaleUuids.microbalanceTi)
      ? 'DiFluid Microbalance Ti'
      : 'DiFluid Microbalance';

  @override
  void configureServices(FoundDevice device, List<BleService> services) {
    _difluid = null;
    _acaia = null;
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
    if (isBookooScaleName(device.name)) return;
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
    await _difluid?.start();
    await _acaia?.start();
  }

  @override
  void connectionClosed() {
    _generation++;
    _acaia?.close();
    _acaia = null;
    _difluid?.close();
    _difluid = null;
  }

  @override
  Iterable<ScaleReading> parseReadings(Uint8List packet) =>
      _acaia?.parse(packet) ?? super.parseReadings(packet);

  @override
  ScaleReading? parse(Uint8List packet) {
    if (_acaia case final acaia?) return acaia.parse(packet).lastOrNull;
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
  Future<bool> send(ScaleCommand command) {
    final id = connectedId;
    final generation = _generation;
    final difluid = _difluid;
    final acaia = _acaia;
    if (id == null) return Future.value(false);
    return _commands = _commands.then((_) async {
      if (connectedId != id || generation != _generation) return false;
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
