import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_lock.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';

/// The owner holds the journal write gate for the whole synchronization pass.
/// This adapter additionally coordinates with manual backup/restore operations.
class DriveJournalAdapter implements DriveSyncJournal {
  DriveJournalAdapter({
    required this.backup,
    required this.photos,
    required this.payloads,
    required this.editing,
    required this.canApply,
    this.onApplying,
  });

  final JournalBackup backup;
  final PhotoStore photos;
  final DriveSyncPayloadStore payloads;
  final bool Function() editing;
  final bool Function() canApply;
  final void Function(bool)? onApplying;

  @override
  bool get isEditing => editing();

  Future<DriveSyncPayload> capture() => JournalLock.withJournalLock(
    photos,
    () => backup.database.transaction(
      () async => DriveSyncPayload.prepare(
        await backup.exportJson(),
        await backup.referencedPhotos(photos),
      ),
    ),
  );

  @override
  Future<String> currentHash() async => (await capture()).hash;

  @override
  Future<String> stage(String snapshotId) async {
    final payload = await capture();
    await payloads.write(snapshotId, payload);
    return payload.hash;
  }

  @override
  Future<void> apply(DriveSnapshot snapshot) async {
    if (!canApply() || isEditing) throw StateError('Journal is not locked');
    final payload = await payloads.read(snapshot.id);
    if (payload.hash != snapshot.contentHash) {
      throw const FormatException('Downloaded journal digest mismatch');
    }
    await backup.database.writeGate.withPreferencesLock(() async {
      final source = payload.withLocalPreferences(await backup.exportJson());
      if (!canApply() || isEditing) throw StateError('Journal is not locked');
      onApplying?.call(true);
      try {
        await JournalRestore(backup, photos).replace(source, payload.photos);
      } finally {
        onApplying?.call(false);
      }
    });
  }
}
