import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:path/path.dart' as path;

String driveDigest(List<int> bytes) => sha256.convert(bytes).toString();

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List<Object?>) return value.map(_canonical).toList();
  return value;
}

/// Portable data excludes device preferences. The logical digest covers the
/// journal AND named photo digests, independently of compression and export time.
class DriveSyncPayload {
  factory DriveSyncPayload.create(
    String source,
    Map<String, Uint8List> photos, {
    bool includePreferences = false,
  }) {
    JournalBackup.inspectJson(source);
    final root = jsonDecode(source) as Map<String, dynamic>;
    root.remove('exportedAt');
    final data = root['data'] as Map<String, dynamic>;
    if (!includePreferences) data.remove('preferences');
    // Backup timestamps are bookkeeping, not a new diary revision.
    final digestRoot = jsonDecode(jsonEncode(root)) as Map<String, dynamic>;
    for (final row
        in ((digestRoot['data'] as Map<String, dynamic>)['preferences']
                as List<dynamic>?) ??
            const []) {
      (row as Map<String, dynamic>).remove('lastBackupAtMs');
    }
    final referenced = <String>{};
    for (final collection in [
      'coffeePhotos',
      'brewPhotos',
      'cafeDrinkPhotos',
    ]) {
      for (final row in (data[collection] as List<dynamic>?) ?? const []) {
        final name = (row as Map<String, dynamic>)['fileName'];
        if (name is! String || !PhotoStore.isValidName(name)) {
          throw const FormatException('Invalid synchronization photo name');
        }
        referenced.add(name);
      }
    }
    final frozenPhotos = <String, Uint8List>{};
    final hashes = <String, String>{};
    for (final name in referenced.toList()..sort()) {
      final bytes = photos[name];
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Missing synchronization photo');
      }
      frozenPhotos[name] = Uint8List.fromList(bytes).asUnmodifiableView();
      hashes[name] = driveDigest(bytes);
    }
    final canonicalSource = jsonEncode(_canonical(root));
    final digest = driveDigest(
      utf8.encode(
        jsonEncode({'journal': _canonical(digestRoot), 'photos': hashes}),
      ),
    );
    return DriveSyncPayload._(
      canonicalSource,
      Map.unmodifiable(frozenPhotos),
      Map.unmodifiable(hashes),
      digest,
      includePreferences,
    );
  }
  DriveSyncPayload._(
    this.source,
    this.photos,
    this.photoHashes,
    this.hash,
    this.includePreferences,
  );

  final bool includePreferences;

  static Future<DriveSyncPayload> prepare(
    String source,
    Map<String, Uint8List> photos, {
    bool includePreferences = false,
  }) => Isolate.run(
    () => DriveSyncPayload.create(
      source,
      photos,
      includePreferences: includePreferences,
    ),
  );

  final String source;
  final Map<String, Uint8List> photos;
  final Map<String, String> photoHashes;
  final String hash;

  Future<Uint8List> archive() {
    final source = this.source;
    final photos = this.photos;
    return Isolate.run(() => JournalBackup.encodeArchive(source, photos));
  }

  Uint8List get compressedJournal =>
      Uint8List.fromList(gzip.encode(utf8.encode(source)));

  /// Called while the caller prevents journal and preference writes. Preferences
  /// must be injected, since omitting them would clear them during replacement.
  String withLocalPreferences(String localSource) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final local = jsonDecode(localSource) as Map<String, dynamic>;
    (root['data'] as Map<String, dynamic>)['preferences'] =
        (local['data'] as Map<String, dynamic>)['preferences'];
    return jsonEncode(root);
  }
}

/// Immutable durable staging. A directory is visible only after its contents
/// have been flushed and atomically promoted. A retry cannot replace its bytes.
class DriveSyncPayloadStore {
  DriveSyncPayloadStore(this.directory);
  final Directory directory;

  Directory _directory(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid staged snapshot ID');
    }
    return Directory(path.join(directory.path, id));
  }

  Future<void> write(String id, DriveSyncPayload payload) async {
    final target = _directory(id);
    if (target.existsSync()) {
      if ((await read(id)).hash != payload.hash) {
        throw const FormatException('Cannot replace immutable snapshot');
      }
      return;
    }
    await directory.create(recursive: true);
    final temporary = await directory.createTemp('.stage-');
    try {
      await File(path.join(temporary.path, 'journal.json.gz')).writeAsBytes(
        await Isolate.run(() => payload.compressedJournal),
        flush: true,
      );
      final photos = PhotoStore(Directory(path.join(temporary.path, 'photos')));
      await photos.directory.create();
      for (final entry in payload.photos.entries) {
        await photos.file(entry.key).writeAsBytes(entry.value, flush: true);
      }
      await AtomicJsonFile(File(path.join(temporary.path, 'manifest.json')))
          .write({
            'version': 1,
            'includePreferences': payload.includePreferences,
            'hash': payload.hash,
            'photos': payload.photoHashes,
          });
      await temporary.rename(target.path);
    } finally {
      if (temporary.existsSync()) await temporary.delete(recursive: true);
    }
  }

  Future<void> remove(String id) async {
    final target = _directory(id);
    if (target.existsSync()) await target.delete(recursive: true);
  }

  Future<DriveSyncPayload> read(String id) async {
    final target = _directory(id);
    final manifest = await AtomicJsonFile(
      File(path.join(target.path, 'manifest.json')),
    ).read();
    if (manifest is! Map<String, dynamic> || manifest['version'] != 1) {
      throw const FormatException('Unsupported staged snapshot');
    }
    final compressed = await File(path.join(target.path, 'journal.json.gz'))
        .readAsBytes();
    final source = await Isolate.run(
      () => utf8.decode(gzip.decode(compressed)),
    );
    final photos = await PhotoStore(Directory(path.join(target.path, 'photos')))
        .readAll();
    final payload = await DriveSyncPayload.prepare(
      source,
      photos,
      includePreferences: manifest['includePreferences'] == true,
    );
    if (manifest['hash'] != payload.hash ||
        jsonEncode(_canonical(manifest['photos'])) !=
            jsonEncode(payload.photoHashes)) {
      throw const FormatException('Corrupt staged snapshot');
    }
    return payload;
  }
}
