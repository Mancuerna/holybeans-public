import 'dart:io';

import 'package:holybeans/data/preferences/current_release.g.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ReleaseNotesSettings {
  ReleaseNotesSettings(File file, {this.version = currentReleaseVersion})
    : _json = AtomicJsonFile(file);

  final String version;
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
    final seen = saved is Map ? saved['seenVersion'] : null;
    if (seen is String && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(seen)) {
      final previous = seen.split('.').map(int.parse).toList();
      final current = version.split('.').map(int.parse).toList();
      for (var index = 0; index < current.length; index++) {
        if (current[index] != previous[index]) {
          return current[index] > previous[index];
        }
      }
      return false;
    }
    // Legacy numeric revisions cannot identify a version. Show the current
    // notes once on existing installations, then persist the version.
    if (existingInstallation) return true;
    await markSeen();
    return false;
  }

  Future<void> markSeen() => _json.write({'seenVersion': version});
}
