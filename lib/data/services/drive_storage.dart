import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class DriveConfiguration {
  const DriveConfiguration({
    required this.deviceId,
    required this.account,
    required this.enabled,
  });
  final String deviceId;
  final String? account;
  final bool enabled;
}

/// Keeps the installed Drive opt-in path, identity and temporary exports.
class DriveStorage {
  DriveStorage(this.directory)
    : config = AtomicJsonFile(File(path.join(directory.path, 'config.json')));
  factory DriveStorage.forPhotos(PhotoStore photos) => DriveStorage(
    Directory(path.join(path.dirname(photos.directory.path), 'drive-sync')),
  );
  final Directory directory;
  final AtomicJsonFile config;
  String newDeviceId() => const Uuid().v4();

  Future<DriveConfiguration> read() async {
    final saved = await config.read();
    if (saved != null && saved is! Map<String, dynamic>) {
      throw const FormatException('Invalid Drive configuration');
    }
    final value = saved as Map<String, dynamic>?;
    if (value != null &&
        (value['version'] != 1 ||
            value['enabled'] is! bool ||
            value['device'] is! String ||
            (value['account'] != null && value['account'] is! String))) {
      throw const FormatException('Unsupported Drive configuration');
    }
    final device = value?['device'] as String? ?? newDeviceId();
    final account = value?['account'] as String?;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(device) ||
        (account != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(account))) {
      throw const FormatException('Invalid Drive identity');
    }
    return DriveConfiguration(
      deviceId: device,
      account: account,
      enabled: value?['enabled'] == true,
    );
  }

  Future<void> save(DriveConfiguration value) => config.write({
    'version': 1,
    'device': value.deviceId,
    'account': value.account,
    'enabled': value.enabled,
    'mode': 'backup',
  });

  DriveBackups backups({
    required JournalBackup backup,
    required PhotoStore photos,
    required String deviceId,
    required String account,
    required DriveNativeClient client,
  }) => DriveBackups(
    backup: backup,
    photos: photos,
    directory: directory,
    deviceId: deviceId,
    account: account,
    client: client,
  );

  Future<void> share(DriveSyncPayload payload) async {
    final bytes = await payload.archive();
    final file = File(path.join(directory.path, 'holybeans-drive-backup.zip'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } finally {
      if (file.existsSync()) await file.delete();
    }
  }
}
