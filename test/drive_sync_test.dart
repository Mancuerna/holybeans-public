import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/drive_sync_state.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;

final a = 'a' * 64;
final b = 'b' * 64;
final c = 'c' * 64;
DriveSnapshot node(
  String id, {
  String? base,
  String? hash,
  List<String> resolves = const [],
}) => DriveSnapshot(
  id: id,
  deviceId: 'phone',
  contentHash: hash ?? a,
  createdAt: DateTime.utc(2026),
  baseId: base,
  resolvedHeads: resolves,
);

void main() {
  test('branches remain until explicitly acknowledged by a resolution', () {
    final nodes = [
      node('root'),
      node('left', base: 'root'),
      node('right', base: 'root'),
    ];
    expect(DriveGraph(nodes).heads, {'left', 'right'});
    final resolved = DriveGraph([
      ...nodes,
      node('chosen', base: 'left', resolves: ['left', 'right']),
    ]);
    expect(resolved.heads, {'chosen'});
    expect(resolved['right'], isNotNull);
    expect(resolved.descendsFrom('chosen', 'right'), isTrue);
    // A concurrently written child is not hidden by a stale resolution.
    expect(
      DriveGraph([...nodes, resolved['chosen']!, node('late', base: 'right')])
          .heads,
      {'chosen', 'late'},
    );
  });

  test('rejects incomplete, cyclic and contradictory histories', () {
    expect(
      () => DriveGraph([node('child', base: 'missing')]),
      throwsFormatException,
    );
    expect(
      () => DriveGraph([node('one', base: 'two'), node('two', base: 'one')]),
      throwsFormatException,
    );
    expect(
      () => DriveGraph([node('same'), node('same', hash: b)]),
      throwsFormatException,
    );
    expect(DriveGraph([node('same'), node('same')]).heads, {'same'});
    expect(
      () => DriveSnapshot.fromJson({...node('one').toJson(), 'version': 2}),
      throwsFormatException,
    );
    expect(() => node('../path'), throwsFormatException);
  });

  test('long histories do not need recursive graph traversal', () {
    final graph = DriveGraph(
      List.generate(
        12000,
        (i) => node('s$i', base: i == 0 ? null : 's${i - 1}'),
      ),
    );
    expect(graph.heads, {'s11999'});
    expect(graph.descendsFrom('s11999', 's0'), isTrue);
  });

  test('only clean local content accepts a descendant', () {
    final graph = DriveGraph([
      node('root'),
      node('next', base: 'root', hash: b),
    ]);
    expect(
      decideDriveSync(
        graph: graph,
        localHash: a,
        anchorId: 'root',
        anchorHash: a,
      ),
      DriveSyncDecision.download,
    );
    expect(
      decideDriveSync(
        graph: graph,
        localHash: c,
        anchorId: 'root',
        anchorHash: a,
      ),
      DriveSyncDecision.conflict,
    );
    expect(
      decideDriveSync(
        graph: graph,
        localHash: b,
        anchorId: null,
        anchorHash: null,
      ),
      DriveSyncDecision.initialChoice,
    );
    expect(
      decideDriveSync(
        graph: DriveGraph([]),
        localHash: a,
        anchorId: 'root',
        anchorHash: a,
      ),
      DriveSyncDecision.conflict,
    );
  });

  late Directory directory;
  late DriveSyncStateStore store;
  late _Journal journal;
  late _Remote remote;
  DriveSyncCoordinator coordinator() => DriveSyncCoordinator(
    store: store,
    remote: remote,
    journal: journal,
    deviceId: 'phone',
  );
  Future<void> anchored() => store.write(
    DriveSyncState(
      accountKey: 'account',
      deviceId: 'phone',
      anchor: DriveSyncAnchor('root', a),
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('holybeans-drive-state-');
    store = DriveSyncStateStore(
      AtomicJsonFile(File(path.join(directory.path, 'state.json'))),
    );
    journal = _Journal(a);
    remote = _Remote();
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'publication survives a lost response without another ID or upload',
    () async {
      remote.loseResponse = true;
      await expectLater(coordinator().synchronize(), throwsStateError);
      final pending = (await store.read())!.pending!;
      expect(pending.id, 'reserved1');
      expect(remote.nodes.single.id, pending.id);
      expect(await coordinator().synchronize(), DriveSyncStatus.current);
      expect(remote.reservations, 1);
      expect(remote.publications, 1);
      expect((await store.read())!.pending, isNull);
    },
  );

  test(
    'new edits during upload stay dirty and become the next child',
    () async {
      remote.onPublish = () => journal.hash = b;
      expect(await coordinator().synchronize(), DriveSyncStatus.pending);
      expect((await store.read())!.anchor!.hash, a);
      remote.onPublish = null;
      expect(await coordinator().synchronize(), DriveSyncStatus.current);
      expect(remote.nodes.last.baseId, remote.nodes.first.id);
      expect(remote.nodes.last.contentHash, b);
    },
  );

  test(
    'a stale pending upload is retained when the other device advanced',
    () async {
      await anchored();
      await store.write(
        DriveSyncState(
          accountKey: 'account',
          deviceId: 'phone',
          anchor: DriveSyncAnchor('root', a),
          pending: node('pending', base: 'root', hash: b),
        ),
      );
      remote.nodes.addAll([node('root'), node('other', base: 'root', hash: c)]);
      expect(await coordinator().synchronize(), DriveSyncStatus.conflict);
      expect((await store.read())!.pending!.id, 'pending');
      expect(remote.publications, 0);
      expect(journal.applies, 0);
    },
  );

  test(
    'committed restore recovers its anchor after a process failure',
    () async {
      await anchored();
      remote.nodes.addAll([node('root'), node('next', base: 'root', hash: b)]);
      journal.failAfterApply = true;
      await expectLater(coordinator().synchronize(), throwsStateError);
      expect(journal.hash, b);
      expect((await store.read())!.applying!.target.id, 'next');
      expect(await coordinator().synchronize(), DriveSyncStatus.current);
      expect(journal.applies, 1);
      expect((await store.read())!.anchor!.id, 'next');
    },
  );

  test(
    'unapplied restore retries, unexpected local content is preserved',
    () async {
      await store.write(
        DriveSyncState(
          accountKey: 'account',
          deviceId: 'phone',
          anchor: DriveSyncAnchor('root', a),
          applying: DriveApplyIntent(
            target: DriveSyncAnchor('next', b),
            previousHash: a,
          ),
        ),
      );
      remote.nodes.addAll([node('root'), node('next', base: 'root', hash: b)]);
      journal.hash = c;
      expect(await coordinator().synchronize(), DriveSyncStatus.conflict);
      expect(journal.applies, 0);
      expect((await store.read())!.applying, isNotNull);
      journal.hash = a;
      expect(await coordinator().synchronize(), DriveSyncStatus.current);
      expect(journal.applies, 1);
    },
  );

  test('an editor opened during download prevents restore', () async {
    await anchored();
    remote.nodes.addAll([node('root'), node('next', base: 'root', hash: b)]);
    remote.onDownload = () => journal.isEditing = true;
    expect(await coordinator().synchronize(), DriveSyncStatus.editing);
    expect(journal.applies, 0);
    expect((await store.read())!.applying, isNull);
  });

  test('corrupt state and account mismatch fail closed', () async {
    await store.file.write({'version': 2});
    await expectLater(coordinator().synchronize(), throwsFormatException);
    expect(remote.publications, 0);
    await store.write(
      DriveSyncState(accountKey: 'different', deviceId: 'phone'),
    );
    expect(await coordinator().synchronize(), DriveSyncStatus.conflict);
    expect(remote.publications, 0);
  });

  test('concurrent requests share one operation', () async {
    final blocked = Completer<void>();
    remote.blockInventory = blocked.future;
    final sync = coordinator();
    final first = sync.synchronize();
    final second = sync.synchronize();
    blocked.complete();
    expect(await first, DriveSyncStatus.current);
    expect(await second, DriveSyncStatus.current);
    expect(remote.publications, 1);
  });
}

class _Journal implements DriveSyncJournal {
  _Journal(this.hash);
  String hash;
  int applies = 0;
  bool failAfterApply = false;
  @override
  bool isEditing = false;
  @override
  Future<String> currentHash() async => hash;
  @override
  Future<String> stage(String snapshotId) async => hash;
  @override
  Future<void> apply(DriveSnapshot snapshot) async {
    applies++;
    hash = snapshot.contentHash;
    if (failAfterApply) {
      throw StateError('Process stopped after journal commit');
    }
  }
}

class _Remote implements DriveSyncRemote {
  final nodes = <DriveSnapshot>[];
  int reservations = 0;
  int publications = 0;
  bool loseResponse = false;
  void Function()? onPublish;
  void Function()? onDownload;
  Future<void>? blockInventory;
  @override
  String get accountKey => 'account';
  @override
  Future<DriveGraph> inventory() async {
    await blockInventory;
    return DriveGraph(nodes);
  }

  @override
  Future<String> reserveId() async => 'reserved${++reservations}';
  @override
  Future<void> publish(DriveSnapshot snapshot) async {
    publications++;
    nodes.add(snapshot);
    onPublish?.call();
    if (loseResponse) throw StateError('Response lost after remote commit');
  }

  @override
  Future<void> download(DriveSnapshot snapshot) async => onDownload?.call();
}
