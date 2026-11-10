import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/ble_scan.dart';
import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:universal_ble/universal_ble.dart';

/// What the Bluetooth devices share: searching by name, pairing,
/// reconnecting to the remembered device and listening to one notifying
/// characteristic, whose packets [parse] turns into readings of type [T].
/// Subclasses say which device they are; writing to it is up to them.
abstract class BleLink<T extends Object> extends ChangeNotifier
    implements PairedDevice {
  BleLink({this.trace});

  final BleTrace? trace;

  void traceEvent(String event, Map<String, Object?> data) =>
      emitBleTrace(trace, event, data);

  static const _searchTime = Duration(seconds: 12);
  static const _connectTime = Duration(seconds: 15);

  /// The service and characteristic whose notifications carry readings.
  String get service;
  String get characteristic;

  /// Whether a device advertising [name] is one of this kind.
  bool matchesName(String? name);

  /// Whether the advertisement belongs to a supported device.
  bool matchesAdvertisement(BleDevice device) => matchesName(device.name);

  /// Display name when the advertisement omits it.
  String advertisedName(BleDevice device) => device.name ?? device.deviceId;

  /// Selects a protocol from the services discovered on this connection.
  @protected
  void configureServices(FoundDevice device, List<BleService> services) {}

  /// Releases protocol work as soon as a connection is closed or lost.
  @protected
  void connectionClosed() {}

  /// A reading from a notification, or null for packets to ignore.
  T? parse(Uint8List packet);

  /// A BLE notification may contain several protocol frames.
  Iterable<T> parseReadings(Uint8List packet) {
    final reading = parse(packet);
    return reading == null ? const [] : [reading];
  }

  /// The device remembered on this phone, and remembering a new one (null
  /// forgets it).
  Future<FoundDevice?> loadRemembered();
  Future<void> saveRemembered(FoundDevice? device);

  /// Runs after notifications are subscribed, before reporting connection.
  @protected
  Future<void> onNotificationsSubscribed(String deviceId) async {}

  /// Runs before explicitly disconnecting a device that is still reachable.
  @protected
  Future<void> beforeDisconnect(String deviceId) async {}

  @protected
  Future<List<FoundDevice>> reconnectCandidates(FoundDevice preferred) async =>
      [preferred];

  @protected
  void cancelReconnect() {}

  @protected
  void setRemembered(FoundDevice? device) {
    _remembered = device;
    _notify();
  }

  bool _opening = false;
  int _attempt = 0;
  FoundDevice? _remembered;
  bool _loaded = false;

  @override
  DeviceStatus status = DeviceStatus.idle;

  /// Last reading while connected.
  T? latest;

  @override
  List<FoundDevice> found = const [];

  @override
  bool hasSearched = false;

  final _readings = StreamController<T>.broadcast();
  StreamSubscription<BleDevice>? _scan;
  BleScanLease? _scanLease;
  StreamSubscription<Uint8List>? _values;
  StreamSubscription<bool>? _link;
  Timer? _searchEnd;
  String? _deviceId;
  bool _disposed = false;

  /// The user disconnected it: the app does not reconnect by itself.
  bool _heldOff = false;

  /// Name of the remembered device, or null when none is paired.
  @override
  String? get name => _remembered?.name;

  /// Readings as they arrive.
  Stream<T> get readings => _readings.stream;

  @override
  bool get connected => status == DeviceStatus.connected;

  /// The connected device, for subclasses that write to it.
  @protected
  String? get connectedId => connected ? _deviceId : null;

  /// The device being connected or already connected.
  @protected
  String? get connectionTargetId => _deviceId;

  void _set(DeviceStatus value) {
    traceEvent('status', {'previous': status.name, 'next': value.name});
    status = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reads which device is remembered; call once at start.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _remembered = await loadRemembered();
    _notify();
  }

  /// Permission and a powered-on adapter, or the status that explains why
  /// not.
  Future<bool> _ready() async {
    final attempt = _attempt;
    try {
      traceEvent('permissions.request', {});
      await UniversalBle.requestPermissions();
      if (_disposed || attempt != _attempt) return false;
      traceEvent('permissions.granted', {});
    } on Object catch (error, stack) {
      traceEvent('permissions.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      if (!_disposed && attempt == _attempt) _set(DeviceStatus.denied);
      return false;
    }
    try {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      if (_disposed || attempt != _attempt) return false;
      traceEvent('adapter', {'state': state.name});
      if (state != AvailabilityState.poweredOn) {
        _set(DeviceStatus.bluetoothOff);
        return false;
      }
    } on Object catch (error, stack) {
      traceEvent('adapter.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      if (!_disposed && attempt == _attempt) _set(DeviceStatus.bluetoothOff);
      return false;
    }
    return true;
  }

  /// Looks for devices nearby for a few seconds.
  @override
  Future<void> search() async {
    if (_disposed || status == DeviceStatus.searching) return;
    if (_opening) await disconnect();
    final attempt = _attempt;
    if (!await _ready() ||
        _disposed ||
        attempt != _attempt ||
        status == DeviceStatus.searching) {
      return;
    }
    found = const [];
    hasSearched = true;
    _set(DeviceStatus.searching);
    _scan ??= UniversalBle.scanStream.listen((device) {
      if (!matchesAdvertisement(device) ||
          found.any((known) => known.id == device.deviceId)) {
        return;
      }
      found = [
        ...found,
        FoundDevice(id: device.deviceId, name: advertisedName(device)),
      ];
      _notify();
    });
    final lease = _scanLease = sharedBleScan.acquire();
    try {
      traceEvent('scan.start', {});
      await lease.ready;
    } on Object catch (error, stack) {
      traceEvent('scan.error', {
        'error': error.toString(),
        'stack': stack.toString(),
      });
      if (identical(_scanLease, lease)) {
        await stopSearch();
        if (!_disposed && _scanLease == null) _set(DeviceStatus.failed);
      }
      return;
    }
    if (_disposed || !identical(_scanLease, lease)) return;
    _searchEnd = Timer(_searchTime, stopSearch);
  }

  @override
  Future<void> stopSearch() async {
    _searchEnd?.cancel();
    _searchEnd = null;
    final cancelScan = _scan?.cancel();
    final lease = _scanLease;
    _scan = null;
    _scanLease = null;
    await cancelScan;
    try {
      await lease?.release();
      traceEvent('scan.stop', {'supportedDevices': found.length});
    } on Object {
      // Not scanning.
    }
    if (status == DeviceStatus.searching && _scanLease == null) {
      _set(
        _deviceId != null && _link != null
            ? DeviceStatus.connected
            : DeviceStatus.idle,
      );
    }
  }

  /// Connects to [device] and remembers it.
  @override
  Future<void> pair(FoundDevice device) async {
    if (_disposed) return;
    if (_opening) await disconnect();
    if (_disposed) return;
    _opening = true;
    _heldOff = false;
    final attempt = ++_attempt;
    try {
      await stopSearch();
      if (attempt != _attempt || _disposed) return;
      if (await _open(device) && attempt == _attempt && !_disposed) {
        _remembered = device;
        found = const [];
        hasSearched = false;
        await saveRemembered(device);
        _notify();
      }
    } finally {
      if (attempt == _attempt) _opening = false;
    }
  }

  /// Reconnects only to known devices, keeping an existing connection intact.
  @override
  Future<void> connect({bool automatic = false}) async {
    if (_opening ||
        _disposed ||
        status == DeviceStatus.searching ||
        connected) {
      return;
    }
    if (automatic && _heldOff) return;
    if (!automatic) _heldOff = false;
    final remembered = _remembered;
    if (remembered == null) return;
    _opening = true;
    final attempt = ++_attempt;
    try {
      if (!await _ready() || attempt != _attempt || _disposed) return;
      _set(DeviceStatus.connecting);
      final candidates = await reconnectCandidates(remembered);
      for (final device in candidates) {
        if (attempt != _attempt || _disposed) return;
        if (await _open(device)) {
          if (attempt != _attempt || _disposed) return;
          _remembered = device;
          if (device.id != remembered.id) await saveRemembered(device);
          _notify();
          return;
        }
      }
      if (candidates.isEmpty && attempt == _attempt && !_disposed) {
        _set(DeviceStatus.idle);
      }
    } on Object catch (error, stack) {
      traceEvent('reconnect.error', {'error': '$error', 'stack': '$stack'});
      if (attempt == _attempt && !_disposed) _set(DeviceStatus.failed);
    } finally {
      if (attempt == _attempt) _opening = false;
    }
  }

  Future<bool> _open(FoundDevice device) async {
    final attempt = _attempt;
    await _close(disconnect: true);
    if (attempt != _attempt || _disposed) return false;
    final id = device.id;
    _deviceId = id;
    _set(DeviceStatus.connecting);
    try {
      traceEvent('connect.start', {'id': id, 'name': device.name});
      await UniversalBle.connect(id, timeout: _connectTime);
      if (!await _stillOpening(id, attempt)) return false;
      traceEvent('connect.linked', {'id': id});
      final services = await UniversalBle.discoverServices(id);
      if (!await _stillOpening(id, attempt)) return false;
      traceEvent('gatt.services', bleServices(services));
      configureServices(device, services);
      traceEvent('gatt.selected', {
        'service': service,
        'characteristic': characteristic,
      });
      _values = UniversalBle.characteristicValueStream(id, characteristic)
          .listen(
            _onPacket,
            onError: (Object error, StackTrace stack) {
              traceEvent('notification.error', {
                'error': error.toString(),
                'stack': stack.toString(),
              });
            },
          );
      traceEvent('subscribe.start', {'id': id});
      await UniversalBle.subscribeNotifications(id, service, characteristic);
      if (!await _stillOpening(id, attempt)) return false;
      traceEvent('subscribe.ok', {'id': id});
      _link = UniversalBle.connectionStream(id).listen((linked) {
        traceEvent('connection.changed', {'id': id, 'linked': linked});
        if (!linked && _deviceId == id) _lost();
      });
      await onNotificationsSubscribed(id);
      if (!await _stillOpening(id, attempt)) return false;
    } on Object catch (error, stack) {
      traceEvent('connect.error', {
        'id': id,
        'error': error.toString(),
        'stack': stack.toString(),
      });
      if (attempt == _attempt && !_disposed) await _close(disconnect: true);
      if (attempt == _attempt && !_disposed) _set(DeviceStatus.failed);
      return false;
    }
    if (attempt != _attempt || _disposed) return false;
    _set(DeviceStatus.connected);
    return true;
  }

  Future<bool> _stillOpening(String id, int attempt) async {
    if (!_disposed && _deviceId == id && attempt == _attempt) return true;
    // A newer attempt may now own a connection to the same device.
    if (!_disposed && _deviceId == id) return false;
    try {
      await UniversalBle.disconnect(id, timeout: const Duration(seconds: 5));
    } on Object {
      // The cancelled connection may already be closed.
    }
    return false;
  }

  void _onPacket(Uint8List packet) {
    traceEvent('notification.raw', {'bytes': bleHex(packet)});
    for (final parsed in parseReadings(packet)) {
      traceEvent('notification.parsed', {'reading': parsed.toString()});
      latest = parsed;
      _readings.add(parsed);
      _notify();
    }
  }

  /// The device went away (switched off, out of range).
  void _lost() {
    _close();
    _set(DeviceStatus.idle);
  }

  Future<void> _close({bool disconnect = false}) async {
    traceEvent('connection.close', {'id': _deviceId, 'disconnect': disconnect});
    final hadLink = _link != null || connected;
    connectionClosed();
    final cancelValues = _values?.cancel();
    final cancelLink = _link?.cancel();
    final id = _deviceId;
    _values = null;
    _link = null;
    latest = null;
    _deviceId = null;
    await cancelValues;
    await cancelLink;
    if (disconnect && id != null) {
      if (hadLink) {
        try {
          await beforeDisconnect(id);
        } on Object {
          // A failed stop command must not prevent disconnecting.
        }
      }
      try {
        await UniversalBle.disconnect(id, timeout: const Duration(seconds: 5));
      } on Object catch (error) {
        traceEvent('disconnect.error', {'error': error.toString()});
        // Already gone.
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _heldOff = true;
    final attempt = ++_attempt;
    _opening = false;
    cancelReconnect();
    await _close(disconnect: true);
    if (!_disposed && attempt == _attempt) _set(DeviceStatus.idle);
  }

  /// Disconnects and forgets the remembered device.
  @override
  Future<void> forget() async {
    await disconnect();
    _remembered = null;
    await saveRemembered(null);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _attempt++;
    _opening = false;
    cancelReconnect();
    unawaited(stopSearch());
    _close(disconnect: true);
    _readings.close();
    super.dispose();
  }
}
