import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_lock.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class DriveBackupCopy {
  const DriveBackupCopy(this.snapshot, {this.legacy = false});
  final DriveSnapshot snapshot;
  final bool legacy;
}

/// Upload-only backups, independent for each device. Old sync objects are read
/// solely for explicit recovery; no backup ever participates in their graph.
class DriveBackups {
  DriveBackups({
    required this.backup,
    required this.photos,
    required this.directory,
    required this.deviceId,
    required String account,
    required DriveNativeClient client,
  }) {
    final base = Directory(path.join(directory.path, account, 'backups'));
    stateFile = AtomicJsonFile(File(path.join(base.path, 'state.json')));
    payloads = DriveSyncPayloadStore(
      Directory(path.join(base.path, 'payloads')),
    );
    remote = DriveRemoteAdapter(
      accountKey: account,
      client: client,
      payloads: payloads,
      photoQueue: AtomicJsonFile(File(path.join(base.path, 'photos.json'))),
      backupMode: true,
    );
    legacy = DriveRemoteAdapter(
      accountKey: account,
      client: client,
      payloads: payloads,
      photoQueue: AtomicJsonFile(
        File(path.join(base.path, 'legacy-photos.json')),
      ),
    );
  }

  final JournalBackup backup;
  final PhotoStore photos;
  final Directory directory;
  final String deviceId;
  late final AtomicJsonFile stateFile;
  late final DriveSyncPayloadStore payloads;
  late final DriveRemoteAdapter remote;
  late final DriveRemoteAdapter legacy;
  DateTime? lastBackupAt;

  Future<DriveSyncPayload> capture() async {
    // Release the database transaction before validation, hashing, compression
    // or any network I/O. A missing/deleted photo fails the copy, never a save.
    final (source, files) = await JournalLock.withJournalLock(photos, () async {
      final source = await backup.exportJsonInBackground();
      // Read only photos named by this immutable source, after releasing the
      // database. Unrelated and historical photos never delay a journal save.
      final files = <String, Uint8List>{};
      for (final name in await _photoNames(source)) {
        files[name] = await photos.file(name).readAsBytes();
      }
      return (source, files);
    });
    return DriveSyncPayload.prepare(source, files, includePreferences: true);
  }

  Future<Map<String, dynamic>> _state() async {
    final value = await stateFile.read();
    if (value == null) return {'version': 1};
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('Invalid Drive backup state');
    }
    return value;
  }

  Future<void> load() async {
    final state = await _state();
    lastBackupAt = DateTime.tryParse(state['completedAt'] as String? ?? '');
  }

  Future<void> _finish(DriveSnapshot snapshot) async {
    await remote.publish(snapshot);
    lastBackupAt = DateTime.now().toUtc();
    await stateFile.write({
      'version': 1,
      'hash': snapshot.contentHash,
      'completed': snapshot.toJson(),
      'completedAt': lastBackupAt!.toIso8601String(),
    });
    await payloads.remove(snapshot.id);
  }

  Future<void> save() async {
    var state = await _state();
    final pending = state['pending'];
    if (pending != null) {
      // Retry the same immutable ID after an uncertain upload, even on restart.
      await _finish(DriveSnapshot.fromJson(pending));
      state = await _state();
    }
    final payload = await capture();
    if (payload.hash == state['hash'] && state['completed'] != null) {
      final completed = DriveSnapshot.fromJson(state['completed']);
      final copies = await remote.listCopies();
      if (copies.any((copy) => copy.sameAs(completed))) {
        await load();
        await _retain(completed, copies);
        return;
      }
    }
    final snapshot = DriveSnapshot(
      id: await remote.reserveId(),
      deviceId: deviceId,
      contentHash: payload.hash,
      createdAt: DateTime.now(),
    );
    await payloads.write(snapshot.id, payload);
    await stateFile.write({...state, 'pending': snapshot.toJson()});
    await _finish(snapshot);
    await _retain(snapshot, await remote.listCopies());
  }

  Future<void> _retain(
    DriveSnapshot completed,
    List<DriveSnapshot> copies,
  ) async {
    // Retain the verified current copy plus four others, even if this phone's
    // clock moved backwards. Never remove other devices, legacy or photo files.
    final previous =
        copies
            .where(
              (copy) => copy.deviceId == deviceId && copy.id != completed.id,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final copy in previous.skip(4)) {
      await remote.removeBackup(copy);
    }
  }

  Future<List<DriveBackupCopy>> list() async {
    final copies = [
      for (final snapshot in await remote.listCopies())
        DriveBackupCopy(snapshot),
      for (final snapshot in await legacy.listCopies())
        DriveBackupCopy(snapshot, legacy: true),
    ];
    copies.sort((a, b) => b.snapshot.createdAt.compareTo(a.snapshot.createdAt));
    return copies;
  }

  Future<DriveSyncPayload> read(DriveBackupCopy copy) async {
    try {
      await (copy.legacy ? legacy : remote).download(copy.snapshot);
      return await payloads.read(copy.snapshot.id);
    } finally {
      // Downloads share this store with durable uploads. Preserve a pending ID.
      try {
        final pending = (await _state())['pending'];
        if (pending == null ||
            DriveSnapshot.fromJson(pending).id != copy.snapshot.id) {
          await payloads.remove(copy.snapshot.id);
        }
      } catch (error, stack) {
        // Unknown upload state must preserve files without blocking recovery.
        reportError(error, stack);
      }
    }
  }

  Future<void> safetyCopy() async {
    final payload = await capture();
    final bytes = await Isolate.run(
      () => JournalBackup.encodeArchive(payload.source, payload.photos),
    );
    final safety = Directory(path.join(directory.path, 'safety'));
    await safety.create(recursive: true);
    final file = File(path.join(safety.path, '${const Uuid().v4()}.zip'));
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      final written = await temporary.readAsBytes();
      await Isolate.run(() {
        if (driveDigest(written) != driveDigest(bytes)) {
          throw const FormatException('Safety copy verification failed');
        }
        JournalBackup.inspectArchive(written);
      });
      await temporary.rename(file.path);
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
    try {
      await _retainSafety(file);
    } catch (error, stack) {
      // Retention failure must not block recovery after saving a verified copy.
      reportError(error, stack);
    }
  }

  Future<void> _retainSafety(File current) async {
    final previous = <(File, DateTime)>[];
    final name = RegExp(r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}\.zip$');
    await for (final entry in current.parent.list()) {
      if (entry is File &&
          entry.path != current.path &&
          name.hasMatch(path.basename(entry.path))) {
        previous.add((entry, entry.lastModifiedSync()));
      }
    }
    previous.sort((a, b) => b.$2.compareTo(a.$2));
    // Always keep the newly verified copy, even if the clock moved backwards.
    for (final (file, _) in previous.skip(4)) {
      await file.delete();
    }
  }

  Future<void> restore(DriveSyncPayload payload) async {
    await backup.database.writeGate.withPreferencesLock(() async {
      // Device-specific preferences (including folder access) remain local.
      final local = await backup.exportJson();
      final source = await _restoreSource(payload, local);
      await JournalRestore(backup, photos).replace(source, payload.photos);
    });
  }
}

Future<String> _restoreSource(DriveSyncPayload payload, String local) =>
    Isolate.run(() => payload.withLocalPreferences(local));

Future<Set<String>> _photoNames(String source) => Isolate.run(() {
  final data =
      (jsonDecode(source) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
  return {
    for (final collection in ['coffeePhotos', 'brewPhotos', 'cafeDrinkPhotos'])
      for (final row in (data[collection] as List<dynamic>?) ?? const [])
        (row as Map<String, dynamic>)['fileName'] as String,
  };
});
