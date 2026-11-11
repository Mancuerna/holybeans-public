import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/drive_sync.dart';

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
}
