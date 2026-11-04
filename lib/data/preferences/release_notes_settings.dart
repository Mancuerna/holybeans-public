import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ReleaseNotesSettings {
  ReleaseNotesSettings(File file, {this.revision = currentRevision})
    : _json = AtomicJsonFile(file);

  // Advance with the user-facing notes, independently of private APK numbers.
  static const currentRevision = 13;
  final int revision;
  final AtomicJsonFile _json;

  static Future<ReleaseNotesSettings> open() async {
    final directory = await getApplicationSupportDirectory();
    return ReleaseNotesSettings(
      File(path.join(directory.path, 'release_notes.json')),
    );
  }

  Future<bool> pending({required bool existingInstallation}) async {
    Object? saved;
    try {
      saved = await _json.read();
    } on FormatException {
      // A damaged presentation preference must not block the journal.
    }
    final seen = saved is Map ? saved['seen'] : null;
    if (seen is int) return seen < revision;
    if (existingInstallation) return true;
    await markSeen();
    return false;
  }

  Future<void> markSeen() => _json.write({'seen': revision});
}
