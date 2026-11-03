import 'dart:io';

import 'package:flutter/services.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// A folder the user picked for daily copies, with Android's lasting access.
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// A folder outside the app (Android's storage access framework) where the
/// user saves daily copies with one tap. Copies there survive uninstalling
/// the app. Only files named like [folderBackupName] are ever replaced or
/// deleted; anything else in the folder is left alone.
abstract interface class BackupFolder {
  /// Opens the system folder picker; null when cancelled.
  Future<PickedFolder?> pick();

  /// Whether the app can still write to [uri] (the folder may have been
  /// deleted or its access revoked).
  Future<bool> isAvailable(String uri);

  /// Gives up the lasting access to a folder no longer used.
  Future<void> release(String uri);

  /// Saves [bytes] as the copy of [day], replacing that day's earlier one,
  /// and keeps only the newest [folderBackupsKept] daily copies.
  Future<void> save(String uri, Uint8List bytes, DateTime day);
}

/// [BackupFolder] backed by MainActivity's "holybeans/backups" channel.
class AndroidBackupFolder implements BackupFolder {
  const AndroidBackupFolder();

  static const _channel = MethodChannel('holybeans/backups');

  @override
  Future<PickedFolder?> pick() async {
    final picked = await _channel.invokeMapMethod<String, String>('pick');
    if (picked == null) return null;
    return PickedFolder(uri: picked['uri']!, name: picked['name'] ?? '');
  }

  @override
  Future<bool> isAvailable(String uri) async =>
      await _channel.invokeMethod<bool>('isAvailable', {'uri': uri}) ?? false;

  @override
  Future<void> release(String uri) =>
      _channel.invokeMethod<void>('release', {'uri': uri});

  @override
  Future<void> save(String uri, Uint8List bytes, DateTime day) async {
    // The ZIP goes through a private file rather than the channel.
    final cache = await getTemporaryDirectory();
    final operation = await cache.createTemp('holybeans-folder-copy-');
    final source = File(path.join(operation.path, 'copy.zip'));
    try {
      await source.writeAsBytes(bytes, flush: true);
      await _channel.invokeMethod<void>('write', {
        'uri': uri,
        'name': folderBackupName(day),
        'path': source.path,
      });
    } finally {
      await operation.delete(recursive: true);
    }
    final names = await _channel.invokeListMethod<String>('list', {'uri': uri});
    final stale = staleBackups(
      folderBackupNames(names ?? const []),
      folderBackupsKept,
    );
    if (stale.isNotEmpty) {
      await _channel.invokeMethod<void>('delete', {'uri': uri, 'names': stale});
    }
  }
}
