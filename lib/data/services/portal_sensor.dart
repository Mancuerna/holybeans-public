import 'dart:typed_data';

import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/portal_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

class BlePortalSensor extends BleLink<PortalReading> {
  BlePortalSensor(this.store);
  final PairedDeviceFile store;
  static Future<PairedDeviceFile> openStore() =>
      PairedDeviceFile.open('portal.json');
  @override
  String get service => PortalProtocol.service;
  @override
  String get characteristic => PortalProtocol.measurement;
  @override
  bool matchesName(String? name) {
    final text = name?.toLowerCase() ?? '';
    return text.startsWith('portal') || text.startsWith('belka');
  }

  @override
  bool matchesAdvertisement(BleDevice device) =>
      matchesName(device.name) ||
      device.services.any(
        (uuid) => BleUuidParser.stringOrNull(uuid) == service,
      );
  @override
  PortalReading? parse(Uint8List packet) => PortalProtocol.parse(packet);
  @override
  Future<FoundDevice?> loadRemembered() => store.load();
  @override
  Future<void> saveRemembered(FoundDevice? device) => store.save(device);

  Future<void> displayGraph(bool visible) async {
    final id = connectedId;
    if (id == null) return;
    await UniversalBle.write(
      id,
      service,
      PortalProtocol.command,
      Uint8List.fromList(
        visible ? PortalProtocol.showGraph : PortalProtocol.hideGraph,
      ),
      timeout: const Duration(seconds: 3),
    );
  }
}
