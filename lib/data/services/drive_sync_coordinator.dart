import 'package:holybeans/data/services/drive_sync_state.dart';
import 'package:holybeans/domain/drive_sync.dart';

/// The adapter stages immutable journal/photo bytes before returning their hash.
/// Stage identifiers are snapshot IDs, never paths supplied by the remote peer.
abstract interface class DriveSyncJournal {
  Future<String> currentHash();
  Future<String> stage(String snapshotId);
  Future<void> apply(DriveSnapshot snapshot);
  bool get isEditing;
}

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

/// Serializes synchronization. The caller closes its write gate before invoking
/// this coordinator and only reopens it after [DriveSyncStatus.current].
class DriveSyncCoordinator {
  DriveSyncCoordinator({
    required this.store,
    required this.remote,
    required this.journal,
    required this.deviceId,
  });

  final DriveSyncStateStore store;
  final DriveSyncRemote remote;
  final DriveSyncJournal journal;
  final String deviceId;
  Future<DriveSyncStatus>? _running;
  DriveSyncStatus status = DriveSyncStatus.checking;

  Future<DriveSyncStatus> synchronize() {
    final running = _running;
    if (running != null) return running;
    final operation = _synchronize();
    _running = operation;
    return operation.whenComplete(() => _running = null);
  }

  Future<DriveSyncStatus> _synchronize() async {
    status = DriveSyncStatus.checking;
    try {
      var state =
          await store.read() ??
          DriveSyncState(accountKey: remote.accountKey, deviceId: deviceId);
      if (state.accountKey != remote.accountKey || state.deviceId != deviceId) {
        return status = DriveSyncStatus.conflict;
      }
      var hash = await journal.currentHash();
      final applying = state.applying;
      if (applying != null) {
        if (hash != applying.target.hash && hash != applying.previousHash) {
          return status = DriveSyncStatus.conflict;
        }
        state = DriveSyncState(
          accountKey: state.accountKey,
          deviceId: deviceId,
          anchor: hash == applying.target.hash ? applying.target : state.anchor,
        );
        await store.write(state);
      }
      var graph = await remote.inventory();
      final pending = state.pending;
      if (pending != null) {
        final committed = graph[pending.id];
        if (committed != null && !committed.sameAs(pending)) {
          return status = DriveSyncStatus.conflict;
        }
        if (committed != null) {
          // A lost response is reconciled against bytes, not just properties.
          await remote.download(pending);
        }
        if (committed == null) {
          // Do not publish a stale queue after another device advanced. Keep
          // both the staged payload and pending intent for explicit recovery.
          final resolving =
              pending.resolvedHeads.isNotEmpty &&
              graph.heads.length == pending.resolvedHeads.length &&
              graph.heads.containsAll(pending.resolvedHeads);
          if (!resolving &&
              ((graph.isEmpty && pending.baseId != null) ||
                  (!graph.isEmpty && graph.singleHead?.id != pending.baseId))) {
            return status = DriveSyncStatus.conflict;
          }
          await remote.publish(pending);
          graph = await remote.inventory();
          if (graph[pending.id]?.sameAs(pending) != true) {
            return status = DriveSyncStatus.pending;
          }
        }
        state = DriveSyncState(
          accountKey: state.accountKey,
          deviceId: deviceId,
          anchor: DriveSyncAnchor(pending.id, pending.contentHash),
        );
        await store.write(state);
        hash = await journal.currentHash();
      }
      final decision = decideDriveSync(
        graph: graph,
        localHash: hash,
        anchorId: state.anchor?.id,
        anchorHash: state.anchor?.hash,
      );
      switch (decision) {
        case DriveSyncDecision.current:
          return status = DriveSyncStatus.current;
        case DriveSyncDecision.initialChoice:
          return status = DriveSyncStatus.initialChoice;
        case DriveSyncDecision.conflict:
          return status = DriveSyncStatus.conflict;
        case DriveSyncDecision.download:
          if (journal.isEditing) return status = DriveSyncStatus.editing;
          final snapshot = graph.singleHead!;
          await remote.download(snapshot);
          // Downloads can take time. Recheck local changes and active editors
          // immediately before recording the intent and applying the snapshot.
          if (journal.isEditing) return status = DriveSyncStatus.editing;
          if (await journal.currentHash() != hash) {
            return status = DriveSyncStatus.pending;
          }
          final target = DriveSyncAnchor(snapshot.id, snapshot.contentHash);
          await store.write(
            DriveSyncState(
              accountKey: state.accountKey,
              deviceId: deviceId,
              anchor: state.anchor,
              applying: DriveApplyIntent(target: target, previousHash: hash),
            ),
          );
          await journal.apply(snapshot);
          if (await journal.currentHash() != snapshot.contentHash) {
            return status = DriveSyncStatus.conflict;
          }
          await store.write(
            DriveSyncState(
              accountKey: state.accountKey,
              deviceId: deviceId,
              anchor: target,
            ),
          );
          final after = await remote.inventory();
          return status = after.singleHead?.sameAs(snapshot) == true
              ? DriveSyncStatus.current
              : DriveSyncStatus.pending;
        case DriveSyncDecision.publish:
          final id = await remote.reserveId();
          final stagedHash = await journal.stage(id);
          final snapshot = DriveSnapshot(
            id: id,
            deviceId: deviceId,
            contentHash: stagedHash,
            baseId: state.anchor?.id,
          );
          await store.write(
            DriveSyncState(
              accountKey: state.accountKey,
              deviceId: deviceId,
              anchor: state.anchor,
              pending: snapshot,
            ),
          );
          await remote.publish(snapshot);
          final after = await remote.inventory();
          if (after[snapshot.id]?.sameAs(snapshot) != true) {
            return status = DriveSyncStatus.pending;
          }
          await store.write(
            DriveSyncState(
              accountKey: state.accountKey,
              deviceId: deviceId,
              anchor: DriveSyncAnchor(id, stagedHash),
            ),
          );
          if (after.heads.length != 1) return status = DriveSyncStatus.conflict;
          return status =
              after.singleHead?.id == id &&
                  await journal.currentHash() == stagedHash
              ? DriveSyncStatus.current
              : DriveSyncStatus.pending;
      }
    } catch (_) {
      // Neither authentication nor transport failures discard durable work.
      status = DriveSyncStatus.unavailable;
      rethrow;
    }
  }
}
