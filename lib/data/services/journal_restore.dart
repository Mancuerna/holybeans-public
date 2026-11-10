import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_lock.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:path/path.dart' as path;

/// Coordinates SQLite and photo replacement with an on-disk undo journal.
/// Until the commit marker is durable, reopening restores the previous diary.
class JournalRestore {
  JournalRestore(this.backup, this.photos);

  final JournalBackup backup;
  final PhotoStore photos;

  Directory get _pending => Directory(
    path.join(
      path.dirname(photos.directory.path),
      '${path.basename(photos.directory.path)}.restore',
    ),
  );
  Directory get _staged => Directory(path.join(_pending.path, 'staged'));
  Directory get _previous => Directory(path.join(_pending.path, 'previous'));
  File _file(String name) => File(path.join(_pending.path, name));

  Future<BackupSummary> replace(String source, Map<String, Uint8List> files) =>
      _exclusive(() => _replace(source, files));

  Future<T> _exclusive<T>(Future<T> Function() action) =>
      JournalLock.withJournalLock(photos, action);

  Future<BackupSummary> _replace(
    String source,
    Map<String, Uint8List> files,
  ) async {
    // Fail before staging or moving photos when a synchronized diary is stale.
    backup.database.writeGate.checkWriteAllowed();
    // Reject invalid input before writing anything or replacing the diary.
    JournalBackup.inspectJson(source);
    await _recover();
    if (_pending.existsSync()) {
      throw StateError('Previous restore cleanup is still pending');
    }
    // Photos already on the phone stay, so a backup without them (a plain
    // JSON or an older ZIP) can link them again and undoing it loses none.
    final current = await photos.names();
    final availablePhotos = {...current, ...files.keys};
    JournalBackup.validate(source, availablePhotos.contains);
    await photos.directory.create(recursive: true);
    await _pending.create();
    try {
      await _file('journal.json')
          .writeAsString(await backup.exportJson(), flush: true);
      await photos.stageReplacement(_staged, files);
      await _file('ready').writeAsString('1', flush: true);
      if (photos.directory.existsSync()) {
        await photos.directory.rename(_previous.path);
      }
      await photos.promoteReplacement(_staged);
      final summary = await backup.restoreJson(
        source,
        availablePhotos: availablePhotos,
      );
      // Rename keeps recovery from mistaking a partially written marker for
      // a completed restore. This is the operation's commit point.
      await _file('committed.tmp').writeAsString('1', flush: true);
      await _file('committed.tmp').rename(_file('committed').path);
      if (await _keepPrevious()) await _cleanup();
      return summary;
    } catch (_) {
      // Rollback must still work if the write gate closed during restoration.
      await backup.database.writeGate.restoring(_recover);
      rethrow;
    }
  }

  /// Called before any UI or automatic backup reads the opened database.
  /// Recovery is idempotent, including interruption during recovery itself.
  Future<void> recover() => _exclusive(_recover);

  Future<void> _recover() async {
    if (!_pending.existsSync()) return;
    if (_file('committed').existsSync()) {
      if (await _keepPrevious()) await _cleanup();
      return;
    }
    if (_file('ready').existsSync()) {
      final original = _previous.existsSync() ? PhotoStore(_previous) : photos;
      await backup.restoreJson(
        await _file('journal.json').readAsString(),
        availablePhotos: await original.names(),
      );
      if (_previous.existsSync()) {
        if (photos.directory.existsSync()) {
          await photos.directory.delete(recursive: true);
        }
        await _previous.rename(photos.directory.path);
      }
    }
    await _cleanup();
  }

  /// After the commit, moves back the previous photos the backup did not
  /// replace. If that fails, the folder stays for the next launch to retry,
  /// instead of being deleted with the photos still in it.
  Future<bool> _keepPrevious() async {
    if (!_previous.existsSync()) return true;
    try {
      for (final name in await PhotoStore(_previous).names()) {
        final target = photos.file(name);
        if (!target.existsSync()) {
          await PhotoStore(_previous).file(name).rename(target.path);
        }
      }
      return true;
    } catch (error, stack) {
      developer.log(
        'Keeping previous photos deferred',
        name: 'holybeans',
        error: error,
        stackTrace: stack,
      );
      return false;
    }
  }

  Future<void> _cleanup() async {
    try {
      // Remove the marker last: interrupted cleanup of a committed restore
      // must never cause the database to be rolled back on the next launch.
      for (final entry in [_staged, _previous]) {
        if (entry.existsSync()) await entry.delete(recursive: true);
      }
      for (final name in ['ready', 'journal.json', 'committed.tmp']) {
        final file = _file(name);
        if (file.existsSync()) await file.delete();
      }
      final committed = _file('committed');
      if (committed.existsSync()) await committed.delete();
      await _pending.delete();
    } catch (error, stack) {
      developer.log(
        'Restore cleanup deferred',
        name: 'holybeans',
        error: error,
        stackTrace: stack,
      );
    }
  }
}

extension JournalBackupRestore on JournalBackup {
  /// Restores database and photos with durable recovery on interruption.
  Future<BackupSummary> restoreArchive(
    Uint8List bytes,
    PhotoStore? photos,
  ) async {
    final (source, files) = JournalBackup.readArchive(bytes);
    return restoreWithPhotos(source, files, photos);
  }

  Future<BackupSummary> restoreWithPhotos(
    String source,
    Map<String, Uint8List> files,
    PhotoStore? photos,
  ) => photos == null
      ? restoreJson(source)
      : JournalRestore(this, photos).replace(source, files);
}
