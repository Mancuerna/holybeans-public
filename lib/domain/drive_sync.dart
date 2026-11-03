/// A committed immutable snapshot. Resolution acknowledges all competing heads
/// but keeps the chosen journal whole; it never merges inventory records.
class DriveSnapshot {
  factory DriveSnapshot.fromJson(Object? value) {
    if (value
        case {
          'version': 1,
          'id': final String id,
          'deviceId': final String deviceId,
          'contentHash': final String hash,
          'baseId': final Object? base,
          'createdAt': final String createdAt,
          'resolvedHeads': final List<Object?> heads,
        }
        when (base == null || base is String) &&
            heads.every((h) => h is String)) {
      if (heads.toSet().length != heads.length) {
        throw const FormatException('Duplicate resolved heads');
      }
      return DriveSnapshot(
        id: id,
        deviceId: deviceId,
        contentHash: hash,
        baseId: base as String?,
        createdAt: DateTime.parse(createdAt),
        resolvedHeads: heads.cast<String>(),
      );
    }
    throw const FormatException('Unsupported Drive snapshot');
  }
  DriveSnapshot({
    required this.id,
    required this.deviceId,
    required this.contentHash,
    this.baseId,
    DateTime? createdAt,
    Iterable<String> resolvedHeads = const [],
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc(),
       resolvedHeads = Set.unmodifiable(resolvedHeads) {
    if (!_identifier.hasMatch(id) ||
        !_identifier.hasMatch(deviceId) ||
        !_hash.hasMatch(contentHash) ||
        (baseId != null && !_identifier.hasMatch(baseId!)) ||
        this.resolvedHeads.any((value) => !_identifier.hasMatch(value)) ||
        this.resolvedHeads.contains(id) ||
        baseId == id ||
        (this.resolvedHeads.isNotEmpty &&
            (this.resolvedHeads.length < 2 ||
                !this.resolvedHeads.contains(baseId)))) {
      throw const FormatException('Invalid Drive snapshot');
    }
  }

  static final _identifier = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  final String id;
  final String deviceId;
  final String contentHash;
  final String? baseId;
  final DateTime createdAt;
  final Set<String> resolvedHeads;

  Set<String> get parents => {?baseId, ...resolvedHeads};

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'deviceId': deviceId,
    'contentHash': contentHash,
    'baseId': baseId,
    'createdAt': createdAt.toIso8601String(),
    'resolvedHeads': resolvedHeads.toList()..sort(),
  };

  bool sameAs(DriveSnapshot other) =>
      id == other.id &&
      deviceId == other.deviceId &&
      contentHash == other.contentHash &&
      baseId == other.baseId &&
      createdAt == other.createdAt &&
      resolvedHeads.length == other.resolvedHeads.length &&
      resolvedHeads.containsAll(other.resolvedHeads);
}

class DriveGraph {
  DriveGraph(Iterable<DriveSnapshot> snapshots) {
    for (final snapshot in snapshots) {
      final previous = _nodes[snapshot.id];
      if (previous != null && !previous.sameAs(snapshot)) {
        throw const FormatException('Conflicting snapshot identity');
      }
      _nodes[snapshot.id] = snapshot;
    }
    // Iterative topological validation also handles long histories without
    // overflowing the Dart stack. Missing ancestors fail closed.
    final children = <String, Set<String>>{};
    final remaining = <String, int>{};
    for (final snapshot in _nodes.values) {
      remaining[snapshot.id] = snapshot.parents.length;
      for (final parent in snapshot.parents) {
        if (!_nodes.containsKey(parent)) {
          throw const FormatException('Missing snapshot ancestor');
        }
        children.putIfAbsent(parent, () => {}).add(snapshot.id);
      }
    }
    final ready = [
      for (final id in remaining.keys)
        if (remaining[id] == 0) id,
    ];
    var visited = 0;
    while (ready.isNotEmpty) {
      final id = ready.removeLast();
      visited++;
      for (final child in children[id] ?? const <String>{}) {
        remaining[child] = remaining[child]! - 1;
        if (remaining[child] == 0) ready.add(child);
      }
    }
    if (visited != _nodes.length) {
      throw const FormatException('Cyclic snapshot history');
    }
    heads = Set.unmodifiable(
      _nodes.keys.toSet().difference(children.keys.toSet()),
    );
  }

  final _nodes = <String, DriveSnapshot>{};
  late final Set<String> heads;
  DriveSnapshot? operator [](String id) => _nodes[id];
  bool get isEmpty => _nodes.isEmpty;
  DriveSnapshot? get singleHead =>
      heads.length == 1 ? _nodes[heads.single] : null;

  bool descendsFrom(String descendant, String ancestor) {
    final pending = [descendant];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!seen.add(id)) continue;
      if (id == ancestor && _nodes.containsKey(id)) return true;
      pending.addAll(_nodes[id]?.parents ?? const <String>{});
    }
    return false;
  }
}

enum DriveSyncDecision { current, publish, download, initialChoice, conflict }

DriveSyncDecision decideDriveSync({
  required DriveGraph graph,
  required String localHash,
  required String? anchorId,
  required String? anchorHash,
}) {
  if ((anchorId == null) != (anchorHash == null)) {
    throw const FormatException('Incomplete synchronization anchor');
  }
  if (graph.isEmpty) {
    return anchorId == null
        ? DriveSyncDecision.publish
        : DriveSyncDecision.conflict;
  }
  final head = graph.singleHead;
  if (head == null) return DriveSyncDecision.conflict;
  if (anchorId == null) return DriveSyncDecision.initialChoice;
  final anchor = graph[anchorId];
  if (anchor == null || anchor.contentHash != anchorHash) {
    return DriveSyncDecision.conflict;
  }
  if (head.id == anchorId) {
    return localHash == anchorHash
        ? DriveSyncDecision.current
        : DriveSyncDecision.publish;
  }
  if (localHash == anchorHash && graph.descendsFrom(head.id, anchorId)) {
    return DriveSyncDecision.download;
  }
  return DriveSyncDecision.conflict;
}
