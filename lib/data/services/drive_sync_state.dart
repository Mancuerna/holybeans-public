import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/domain/drive_sync.dart';

class DriveSyncAnchor {
  factory DriveSyncAnchor.fromJson(Object? value) {
    if (value case {'id': final String id, 'hash': final String hash}) {
      // Reuse the protocol's identifier and digest validation.
      DriveSnapshot(
        id: id,
        deviceId: 'validation',
        contentHash: hash,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      return DriveSyncAnchor(id, hash);
    }
    throw const FormatException('Invalid synchronization anchor');
  }
  const DriveSyncAnchor(this.id, this.hash);
  final String id;
  final String hash;

  Map<String, Object?> toJson() => {'id': id, 'hash': hash};
}

/// Persisted before restoring. The previous digest distinguishes an unapplied
/// restore from one committed just before the process stopped.
class DriveApplyIntent {
  factory DriveApplyIntent.fromJson(Object? value) {
    if (value case {
      'target': final Object? target,
      'previousHash': final String hash,
    }) {
      DriveSnapshot(
        id: 'validation',
        deviceId: 'validation',
        contentHash: hash,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      return DriveApplyIntent(
        target: DriveSyncAnchor.fromJson(target),
        previousHash: hash,
      );
    }
    throw const FormatException('Invalid restore intent');
  }
  const DriveApplyIntent({required this.target, required this.previousHash});
  final DriveSyncAnchor target;
  final String previousHash;

  Map<String, Object?> toJson() => {
    'target': target.toJson(),
    'previousHash': previousHash,
  };
}

class DriveSyncState {
  factory DriveSyncState.fromJson(Object? value) {
    if (value case {
      'version': 1,
      'accountKey': final String accountKey,
      'deviceId': final String deviceId,
      'anchor': final Object? anchor,
      'pending': final Object? pending,
      'applying': final Object? applying,
    }) {
      return DriveSyncState(
        accountKey: accountKey,
        deviceId: deviceId,
        anchor: anchor == null ? null : DriveSyncAnchor.fromJson(anchor),
        pending: pending == null ? null : DriveSnapshot.fromJson(pending),
        applying: applying == null ? null : DriveApplyIntent.fromJson(applying),
      );
    }
    throw const FormatException('Unsupported synchronization state');
  }
  DriveSyncState({
    required this.accountKey,
    required this.deviceId,
    this.anchor,
    this.pending,
    this.applying,
  }) {
    DriveSnapshot(
      id: accountKey,
      deviceId: deviceId,
      contentHash: '0' * 64,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    if (pending != null && applying != null) {
      throw const FormatException('Conflicting pending operations');
    }
    if (pending != null &&
        (pending!.deviceId != deviceId || pending!.baseId != anchor?.id)) {
      throw const FormatException(
        'Pending snapshot does not match local anchor',
      );
    }
  }

  final String accountKey;
  final String deviceId;
  final DriveSyncAnchor? anchor;
  final DriveSnapshot? pending;
  final DriveApplyIntent? applying;

  Map<String, Object?> toJson() => {
    'version': 1,
    'accountKey': accountKey,
    'deviceId': deviceId,
    'anchor': anchor?.toJson(),
    'pending': pending?.toJson(),
    'applying': applying?.toJson(),
  };
}

class DriveSyncStateStore {
  DriveSyncStateStore(this.file);
  final AtomicJsonFile file;

  Future<DriveSyncState?> read() async {
    final value = await file.read();
    return value == null ? null : DriveSyncState.fromJson(value);
  }

  Future<void> write(DriveSyncState state) => file.write(state.toJson());
}
