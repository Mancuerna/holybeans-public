import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';

/// Legacy payload fixtures omit preferences; production backups include them.
class DrivePayloadFixture {
  DrivePayloadFixture({
    required this.backup,
    required this.photos,
    required this.payloads,
  });
  final JournalBackup backup;
  final PhotoStore photos;
  final DriveSyncPayloadStore payloads;
  Future<DriveSyncPayload> capture() async => DriveSyncPayload.prepare(
    await backup.exportJson(),
    await backup.referencedPhotos(photos),
  );
  Future<String> currentHash() async => (await capture()).hash;
  Future<String> stage(String id) async {
    final payload = await capture();
    await payloads.write(id, payload);
    return payload.hash;
  }

  Future<void> apply(DriveSnapshot snapshot) async {
    final backups = DriveBackups(
      backup: backup,
      photos: photos,
      directory: payloads.directory.parent,
      deviceId: 'fixture',
      account: 'fixture',
      client: const DriveNativeClient(),
    );
    await backups.restore(await payloads.read(snapshot.id));
  }
}
