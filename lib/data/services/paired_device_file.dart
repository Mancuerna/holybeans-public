import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// A paired Bluetooth device, kept in a small file next to the database:
/// it belongs to this phone, never travels in a backup and needs no schema
/// change.
class PairedDeviceFile {
  PairedDeviceFile(this.file);

  final File file;
  late final _json = AtomicJsonFile(file);

  /// The file [name] in the app's support folder.
  static Future<PairedDeviceFile> open(String name) async {
    final support = await getApplicationSupportDirectory();
    return PairedDeviceFile(File(path.join(support.path, name)));
  }

  Future<FoundDevice?> load() async {
    try {
      final json = await _json.read();
      if (json case {'id': final String id, 'name': final String name}) {
        return FoundDevice(id: id, name: name);
      }
    } on FormatException {
      // A damaged file reads as no device.
    } on FileSystemException {
      // Same.
    }
    return null;
  }

  Future<void> save(FoundDevice? device) => device == null
      ? _json.delete()
      : _json.write({'id': device.id, 'name': device.name});
}
