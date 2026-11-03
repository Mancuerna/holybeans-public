import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Device-local presentation preference, separate from journal backups.
class WaterTargetSettings {
  WaterTargetSettings(this.file);
  final File file;
  late final _json = AtomicJsonFile(file);

  static Future<WaterTargetSettings> open() async {
    final directory = await getApplicationSupportDirectory();
    return WaterTargetSettings(
      File(path.join(directory.path, 'water_targets.json')),
    );
  }

  Future<bool> load() async {
    try {
      final value = await _json.read();
      if (value is Map && value['visible'] is bool) {
        return value['visible'] as bool;
      }
      return true;
    } on FormatException {
      return true;
    } on FileSystemException {
      return true;
    }
  }

  Future<void> save(bool visible) => _json.write({'visible': visible});
}
