import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/domain/drive_sync.dart';

class DriveHttpException implements Exception {
  const DriveHttpException(this.status);
  final int status;
  @override
  String toString() => 'Drive HTTP $status';
}

class DriveNativeClient {
  const DriveNativeClient({
    this.channel = const MethodChannel('holybeans/drive-sync'),
  });
  final MethodChannel channel;

  Future<String> connect({required bool interactive}) async {
    final key = await channel.invokeMethod<String>('connect', {
      'interactive': interactive,
    });
    if (key == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const FormatException('Invalid Drive account identity');
    }
    return key;
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');

  Future<void> disconnect() => channel.invokeMethod<void>('disconnect');

  Future<Map<Object?, Object?>> request(
    String account,
    String url, {
    String method = 'GET',
    Uint8List? body,
    String contentType = 'application/json',
  }) async {
    final response = await channel.invokeMapMethod<Object?, Object?>(
      'request',
      {
        'account': account,
        'url': url,
        'method': method,
        'body': body,
        'contentType': contentType,
      },
    );
    if (response == null ||
        response['status'] is! int ||
        response['body'] is! Uint8List) {
      throw const FormatException('Invalid Drive response');
    }
    return response;
  }
}

/// appData-only append-only storage. Metadata lists the graph without repeatedly
/// downloading historic journals. Photos are reused by verified content digest.
class DriveRemoteAdapter implements DriveSyncRemote {
  DriveRemoteAdapter({
    required this.accountKey,
    required this.client,
    required this.payloads,
    required this.photoQueue,
    this.backupMode = false,
  });

  static const space = String.fromEnvironment(
    'HOLYBEANS_DRIVE_SPACE',
    defaultValue: 'holybeans-journal-v1',
  );
  static const _api = 'https://www.googleapis.com/drive/v3';
  @override
  final String accountKey;
  final DriveNativeClient client;
  final DriveSyncPayloadStore payloads;
  final AtomicJsonFile photoQueue;
  final bool backupMode;
  String get _kind => backupMode ? 'backup' : 'snapshot';

  String _url(String endpoint, [Map<String, String> query = const {}]) =>
      Uri.parse('$_api/$endpoint').replace(queryParameters: query).toString();

  Future<Map<String, dynamic>> _json(
    String url, {
    String method = 'GET',
    Object? body,
  }) async {
    final response = await client.request(
      accountKey,
      url,
      method: method,
      body: body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
    _check(response);
    final value = jsonDecode(utf8.decode(response['body']! as Uint8List));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Drive JSON');
    }
    return value;
  }

  void _check(Map<Object?, Object?> response) {
    final status = response['status']! as int;
    if (status < 200 || status >= 300) throw DriveHttpException(status);
  }

  Future<List<Map<String, dynamic>>> _list(String kind, {String? hash}) async {
    final files = <Map<String, dynamic>>[];
    final tokens = <String>{};
    String? token;
    do {
      final page = await _json(
        _url('files', {
          'spaces': 'appDataFolder',
          'pageSize': '1000',
          'q':
              "trashed = false and appProperties has { key='space' and value='$space' } and appProperties has { key='kind' and value='$kind' }${hash == null ? '' : " and appProperties has { key='hash' and value='$hash' }"}",
          'fields': 'nextPageToken,incompleteSearch,files(id,appProperties)',
          'pageToken': ?token,
        }),
      );
      if (page['incompleteSearch'] == true || page['files'] is! List<dynamic>) {
        throw const FormatException('Incomplete Drive inventory');
      }
      files.addAll(
        (page['files'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
      token = page['nextPageToken'] as String?;
      if (token != null && !tokens.add(token)) {
        throw const FormatException('Repeated Drive page');
      }
    } while (token != null);
    return files;
  }

  Map<String, String> _properties(DriveSnapshot snapshot) => {
    'space': space,
    'kind': _kind,
    'version': '1',
    'device': snapshot.deviceId,
    'hash': snapshot.contentHash,
    'created': snapshot.createdAt.toIso8601String(),
    if (snapshot.baseId != null) 'base': snapshot.baseId!,
    for (final id in snapshot.resolvedHeads) 'r_$id': '1',
  };

  DriveSnapshot _snapshot(Map<String, dynamic> file) {
    final props = file['appProperties'] as Map<String, dynamic>;
    if (props['version'] != '1' ||
        props['space'] != space ||
        props['kind'] != _kind) {
      throw const FormatException('Unsupported remote snapshot');
    }
    return DriveSnapshot(
      id: file['id'] as String,
      deviceId: props['device'] as String,
      contentHash: props['hash'] as String,
      createdAt: DateTime.parse(props['created'] as String),
      baseId: props['base'] as String?,
      resolvedHeads: props.keys
          .where((key) => key.startsWith('r_'))
          .map((key) => key.substring(2)),
    );
  }

  @override
  Future<DriveGraph> inventory() async => DriveGraph(await listCopies());

  Future<List<DriveSnapshot>> listCopies() async =>
      (await _list(_kind)).map(_snapshot).toList();

  Future<void> removeBackup(DriveSnapshot snapshot) async {
    if (!backupMode || snapshot.parents.isNotEmpty) {
      throw StateError('Only independent backups can be removed');
    }
    final response = await client.request(
      accountKey,
      _url('files/${snapshot.id}'),
      method: 'DELETE',
    );
    if (response['status'] != 404) _check(response);
  }

  @override
  Future<String> reserveId() async {
    final response = await _json(
      _url('files/generateIds', {
        'count': '1',
        'space': 'appDataFolder',
        'type': 'files',
      }),
    );
    final ids = response['ids'] as List<dynamic>;
    final id = ids.single as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid Drive ID');
    }
    return id;
  }

  Future<Uint8List?> _read(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid Drive ID');
    }
    final response = await client.request(
      accountKey,
      _url('files/$id', {'alt': 'media'}),
    );
    if (response['status'] == 404) return null;
    _check(response);
    return response['body']! as Uint8List;
  }

  Future<bool?> _matches(
    String id,
    Uint8List bytes, {
    String? photoHash,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid Drive ID');
    }
    if (photoHash != null) {
      try {
        final metadata = await _json(
          _url('files/$id', {'fields': 'sha256Checksum,md5Checksum,size'}),
        );
        final size = int.tryParse(metadata['size'] as String? ?? '');
        if (size != null) {
          if (size != bytes.length) return false;
          if (metadata['sha256Checksum'] case final String digest) {
            return digest == photoHash;
          }
          if (metadata['md5Checksum'] case final String digest) {
            return digest == await _md5(bytes);
          }
        }
      } on DriveHttpException catch (error) {
        if (error.status == 404) return null;
        rethrow;
      }
    }
    // Journals retain byte verification; photos fall back when metadata is absent.
    final existing = await _read(id);
    return existing == null ? null : await _sameBytes(existing, bytes);
  }

  Future<void> _create(
    String id,
    Uint8List bytes,
    Map<String, String> props, {
    String? photoHash,
  }) async {
    final existing = await _matches(id, bytes, photoHash: photoHash);
    if (existing != null) {
      if (!existing) {
        throw const FormatException('Immutable Drive object mismatch');
      }
      return;
    }
    final metadata = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'id': id,
          'name': id,
          'parents': ['appDataFolder'],
          'appProperties': props,
        }),
      ),
    );
    final response = await client.request(
      accountKey,
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable',
      method: 'POST',
      body: metadata,
    );
    _check(response);
    final location = response['location'];
    if (location is! String) {
      throw const FormatException('Missing Drive upload session');
    }
    final uploaded = await client.request(
      accountKey,
      location,
      method: 'PUT',
      body: bytes,
      contentType: 'application/octet-stream',
    );
    _check(uploaded);
    if (await _matches(id, bytes, photoHash: photoHash) != true) {
      throw const FormatException('Drive upload verification failed');
    }
  }

  Future<Map<String, Object?>> _photos(DriveSyncPayload payload) async {
    if (payload.photos.isEmpty) return const {};
    final stored = await photoQueue.read();
    final queue = stored == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(stored as Map);
    final byHash = {
      for (final entry in payload.photos.entries)
        payload.photoHashes[entry.key]!: entry.value,
    };
    final verified = <String>{};
    var changed = false;
    for (final entry in byHash.entries) {
      if (queue[entry.key] != null) continue;
      String? id;
      for (final file in await _list('photo', hash: entry.key)) {
        final candidate = file['id'] as String;
        if (await _matches(candidate, entry.value, photoHash: entry.key) ==
            true) {
          id = candidate;
          verified.add(entry.key);
          break;
        }
      }
      queue[entry.key] = id ?? await reserveId();
      changed = true;
    }
    // Persist every reservation before uploading, including after an uncertain retry.
    if (changed) await photoQueue.write(queue);
    for (final entry in byHash.entries) {
      if (verified.contains(entry.key)) continue;
      await _create(queue[entry.key] as String, entry.value, {
        'space': space,
        'kind': 'photo',
        'hash': entry.key,
      }, photoHash: entry.key);
    }
    return {
      for (final entry in payload.photoHashes.entries)
        entry.key: {'id': queue[entry.value] as String, 'hash': entry.value},
    };
  }

  @override
  Future<void> publish(DriveSnapshot snapshot) async {
    final payload = await payloads.read(snapshot.id);
    if (payload.hash != snapshot.contentHash) {
      throw const FormatException('Staged snapshot mismatch');
    }
    final references = await _photos(payload);
    final bytes = await Isolate.run(
      () => Uint8List.fromList(
        gzip.encode(
          utf8.encode(
            jsonEncode({
              'snapshot': snapshot.toJson(),
              'journal': payload.source,
              'photos': references,
            }),
          ),
        ),
      ),
    );
    await _create(snapshot.id, bytes, _properties(snapshot));
  }

  @override
  Future<void> download(DriveSnapshot snapshot) async {
    final bytes = await _read(snapshot.id);
    if (bytes == null) {
      throw const FormatException('Remote snapshot disappeared');
    }
    final output = BytesBuilder(copy: false);
    await for (final chunk in gzip.decoder.bind(Stream.value(bytes))) {
      if (output.length + chunk.length > 256 * 1024 * 1024) {
        throw const FormatException('Remote journal exceeds size limit');
      }
      output.add(chunk);
    }
    final envelope = await _decodeEnvelope(output.takeBytes());
    if (!DriveSnapshot.fromJson(envelope['snapshot']).sameAs(snapshot)) {
      throw const FormatException('Remote metadata mismatch');
    }
    final references = envelope['photos'] as Map<String, dynamic>;
    final photos = <String, Uint8List>{};
    for (final entry in references.entries) {
      final ref = entry.value as Map<String, dynamic>;
      final photo = await _read(ref['id'] as String);
      if (photo == null || await _digest(photo) != ref['hash']) {
        throw const FormatException('Remote photo mismatch');
      }
      photos[entry.key] = photo;
    }
    final payload = await DriveSyncPayload.prepare(
      envelope['journal'] as String,
      photos,
      includePreferences: backupMode,
    );
    if (payload.hash != snapshot.contentHash ||
        payload.photos.length != references.length) {
      throw const FormatException('Remote content mismatch');
    }
    await payloads.write(snapshot.id, payload);
  }
}

Future<bool> _sameBytes(Uint8List a, Uint8List b) =>
    Isolate.run(() => driveDigest(a) == driveDigest(b));

Future<String> _digest(Uint8List bytes) =>
    Isolate.run(() => driveDigest(bytes));

Future<String> _md5(Uint8List bytes) =>
    Isolate.run(() => md5.convert(bytes).toString());

Future<Map<String, dynamic>> _decodeEnvelope(Uint8List bytes) =>
    Isolate.run(() => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
