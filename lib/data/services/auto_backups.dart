import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_lock.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// An exported journal with its fingerprint, ready to be saved.
class JournalSnapshot {
  const JournalSnapshot({
    required this.source,
    required this.fingerprint,
    required this.empty,
  });

  final String source;
  final String fingerprint;

  /// Neither coffees nor brews: never worth an automatic copy.
  final bool empty;

  /// Exports the journal; the fingerprint is computed in another isolate.
  /// Takes the journal and referenced photo bytes under the same restore lock.
  static Future<(JournalSnapshot, Map<String, Uint8List>)> takeWithPhotos(
    JournalBackup backup,
    PhotoStore? photos,
  ) => JournalLock.withJournalLock(
    photos,
    () => backup.database.transaction(
      () async => (await take(backup), await backup.referencedPhotos(photos)),
    ),
  );

  static Future<JournalSnapshot> take(JournalBackup backup) async {
    final source = await backup.exportJson();
    final digest = await Isolate.run(() => journalDigest(source));
    return JournalSnapshot(
      source: source,
      fingerprint: digest.fingerprint,
      empty: digest.empty,
    );
  }
}

/// The automatic copies kept inside the app's private storage. Each one is
/// a ZIP with the journal only: photos stay in their own folder on the phone
/// and are kept when one of these copies is restored. Android deletes them
/// with the app, so they protect against mistakes and failed updates, not
/// against losing or resetting the phone.
class AutoBackups {
  AutoBackups(this.directory);

  final Directory directory;

  static Future<AutoBackups> open() async {
    final support = await getApplicationSupportDirectory();
    return AutoBackups(Directory(path.join(support.path, 'auto-backups')));
  }

  /// The copies, newest first.
  Future<List<AutoBackupEntry>> list() async {
    if (!directory.existsSync()) return const [];
    return autoBackupEntries([
      await for (final entry in directory.list())
        if (entry is File) path.basename(entry.path),
    ]);
  }

  File file(AutoBackupEntry entry) =>
      File(path.join(directory.path, entry.fileName));

  Future<Uint8List> read(AutoBackupEntry entry) => file(entry).readAsBytes();

  /// Saves [snapshot] when [autoBackupNeeded] says so, then keeps only the
  /// newest [autoBackupsKept]. Returns the new copy, or null if none was due.
  Future<AutoBackupEntry?> saveIfNeeded(
    JournalSnapshot snapshot, {
    required DateTime now,
    bool force = false,
  }) async {
    final entries = await list();
    if (!autoBackupNeeded(
      entries: entries,
      fingerprint: snapshot.fingerprint,
      journalEmpty: snapshot.empty,
      now: now,
      force: force,
    )) {
      return null;
    }
    final source = snapshot.source;
    final bytes = await Isolate.run(
      () => JournalBackup.encodeArchive(source, const {}),
    );
    await directory.create(recursive: true);
    final name = AutoBackupEntry.nameFor(now, snapshot.fingerprint);
    // Written aside and renamed, so a copy is either complete or absent.
    final temporary = File(path.join(directory.path, '.$name.tmp'));
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path.join(directory.path, name));
    final saved = await list();
    for (final stale in staleBackups([
      for (final entry in saved) entry.fileName,
    ], autoBackupsKept)) {
      await File(path.join(directory.path, stale)).delete();
    }
    return AutoBackupEntry.parse(name);
  }
}
