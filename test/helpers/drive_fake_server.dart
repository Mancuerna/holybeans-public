import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class _Stored {
  _Stored(this.properties, this.bytes);
  final Map<String, dynamic> properties;
  Uint8List bytes;
}

class DriveFakeServer {
  final files = <String, _Stored>{};
  final sessions = <String, Map<String, dynamic>>{};
  int nextId = 0;
  int mediaReads = 0;
  int photoMediaReads = 0;
  int photoMediaBytes = 0;
  bool omitChecksums = false;
  bool omitSha256 = false;
  bool corruptUploads = false;
  bool loseNextUpload = false;
  bool incomplete = false;
  bool offline = false;

  Map<String, Object?> response(
    Object? value, {
    int status = 200,
    String? location,
  }) => {
    'status': status,
    'body': value is Uint8List
        ? value
        : Uint8List.fromList(utf8.encode(jsonEncode(value))),
    'location': location,
  };

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'connect') return 'a' * 64;
    if (call.method == 'disconnect' || call.method == 'cancel') return null;
    if (offline) throw PlatformException(code: 'network');
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final uri = Uri.parse(args['url'] as String);
    final method = args['method'];
    if (uri.path.endsWith('generateIds')) {
      return response({
        'ids': ['file${++nextId}'],
      });
    }
    if (method == 'DELETE') {
      files.remove(uri.pathSegments.last);
      return response({}, status: 204);
    }
    if (method == 'POST') {
      final metadata = jsonDecode(
        utf8.decode(args['body'] as Uint8List),
      ) as Map<String, dynamic>;
      final id = metadata['id'] as String;
      sessions[id] = metadata;
      return response(
        {},
        location: 'https://www.googleapis.com/upload/drive/v3/session/$id',
      );
    }
    if (method == 'PUT') {
      final id = uri.pathSegments.last;
      files[id] = _Stored(
        sessions[id]!['appProperties'] as Map<String, dynamic>,
        corruptUploads ? Uint8List.fromList([9]) : args['body'] as Uint8List,
      );
      if (loseNextUpload) {
        loseNextUpload = false;
        throw PlatformException(code: 'network');
      }
      return response({'id': id});
    }
    if (uri.path.endsWith('/files')) {
      final query = uri.queryParameters['q']!;
      final kind = query.contains("value='snapshot'")
          ? 'snapshot'
          : query.contains("value='backup'")
          ? 'backup'
          : 'photo';
      final candidates = files.entries
          .where((entry) => entry.value.properties['kind'] == kind)
          .toList();
      final start = int.parse(uri.queryParameters['pageToken'] ?? '0');
      return response({
        'incompleteSearch': incomplete,
        'files': [
          if (start < candidates.length)
            {
              'id': candidates[start].key,
              'appProperties': candidates[start].value.properties,
            },
        ],
        if (start + 1 < candidates.length) 'nextPageToken': '${start + 1}',
      });
    }
    final file = files[uri.pathSegments.last];
    if (uri.queryParameters['alt'] != 'media') {
      return file == null
          ? response({}, status: 404)
          : response({
              'size': '${file.bytes.length}',
              if (!omitChecksums) ...{
                'md5Checksum': md5.convert(file.bytes).toString(),
                if (!omitSha256)
                  'sha256Checksum': sha256.convert(file.bytes).toString(),
              },
            });
    }
    mediaReads++;
    if (file?.properties['kind'] == 'photo') {
      photoMediaReads++;
      photoMediaBytes += file!.bytes.length;
    }
    return file == null ? response({}, status: 404) : response(file.bytes);
  }
}
