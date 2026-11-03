import 'dart:convert';

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
        args['body'] as Uint8List,
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
    mediaReads++;
    final file = files[uri.pathSegments.last];
    return file == null ? response({}, status: 404) : response(file.bytes);
  }
}
