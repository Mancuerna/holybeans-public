import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/bookoo_pressure_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

export 'package:holybeans/data/services/paired_device.dart';

/// A Bluetooth pressure sensor whose transmission the app starts and stops.
///
/// It never changes zeroing, settings or calibration.
abstract interface class PressureSensor implements PairedDevice {
  /// Last pressure in bar while connected.
  double? get bar;

  /// Pressure readings in bar as they arrive.
  Stream<double> get readings;
}

/// A BOOKOO Espresso Monitor that subscribes to pressure notifications.
class BlePressureSensor extends BleLink<double> implements PressureSensor {
  BlePressureSensor(this.store);

  /// Opens the file that remembers the sensor on this phone.
  static Future<PairedDeviceFile> openStore() =>
      PairedDeviceFile.open('pressure_sensor.json');

  final PairedDeviceFile store;

  @override
  String get service => BookooPressureUuids.service;

  @override
  String get characteristic => BookooPressureUuids.pressure;

  @override
  bool matchesName(String? name) => isBookooPressureName(name);

  Future<void> _transmission(String deviceId, List<int> frame) =>
      UniversalBle.write(
        deviceId,
        BookooPressureUuids.service,
        BookooPressureUuids.command,
        Uint8List.fromList(frame),
        timeout: const Duration(seconds: 3),
      );

  @override
  Future<void> onNotificationsSubscribed(String deviceId) =>
      _transmission(deviceId, bookooStartPressure);

  @override
  Future<void> beforeDisconnect(String deviceId) =>
      _transmission(deviceId, bookooStopPressure);

  @override
  double? parse(Uint8List packet) => parseBookooPressureBar(packet);

  @override
  Future<FoundDevice?> loadRemembered() async {
    final device = await store.load();
    return matchesName(device?.name) ? device : null;
  }

  @override
  Future<void> saveRemembered(FoundDevice? device) => store.save(device);

  @override
  double? get bar => latest;
}
