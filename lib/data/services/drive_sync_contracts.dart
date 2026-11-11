import 'package:holybeans/domain/drive_sync.dart';

/// All operations are scoped to a verified Google account. A successful upload
/// includes read-back verification of the snapshot and every referenced photo.
abstract interface class DriveSyncRemote {
  String get accountKey;
  Future<DriveGraph> inventory();
  Future<String> reserveId();
  Future<void> publish(DriveSnapshot snapshot);
  Future<void> download(DriveSnapshot snapshot);
}

enum DriveSyncStatus {
  checking,
  current,
  pending,
  editing,
  initialChoice,
  conflict,
  unavailable,
}
