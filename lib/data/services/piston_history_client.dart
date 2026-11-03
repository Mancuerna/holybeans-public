import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

typedef PistonShotIndex = ({String id, int timeMs});

abstract interface class PistonHistorySource {
  Future<String> serial();
  Future<List<PistonShotIndex>> index({int? sinceMs, int limit = 128});
  Future<List<PistonReading>> readings(List<String> ids);
  void close();
}

PistonHistorySource Function(String address) connectPistonHistory =
    PistonHistoryClient.new;

// Only the read-only GET /machine and GET /history handlers documented in
// docs/DATA.md. No redirects, actions, sockets or POST requests.
class PistonHistoryClient implements PistonHistorySource {
  PistonHistoryClient(String address, {HttpClient? client})
    : base = MeticulousClient.normalizeAddress(address),
      _http = client ?? HttpClient();
  final Uri base;
  final HttpClient _http;
  bool _closed = false;

  Future<Object?> _get(String path, Map<String, dynamic> query) async {
    if (_closed) throw StateError('Closed history client');
    final uri = base.replace(
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
    Future<Object?> read() async {
      final request = await _http.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('History HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) {
          throw const FormatException('History response too large');
        }
      }
      return _decodeHistory(bytes);
    }

    try {
      return await read().timeout(const Duration(seconds: 30));
    } on Object {
      close();
      rethrow;
    }
  }

  @override
  Future<String> serial() async {
    final body = await _get('/api/v1/machine', const {});
    final serial = body is Map ? body['serial'] : null;
    if (serial is! String || serial.trim().isEmpty || serial.length > 200) {
      throw const FormatException('Machine has no identity');
    }
    return serial.trim();
  }

  Future<List<Map<String, dynamic>>> _history(
    Map<String, dynamic> query,
  ) async {
    final body = await _get('/api/v1/history', query);
    if (body is! Map || body['history'] is! List) {
      throw const FormatException('Missing history');
    }
    return (body['history'] as List).map((r) {
      if (r is! Map<String, dynamic>) {
        throw const FormatException('Invalid history row');
      }
      return r;
    }).toList();
  }

  @override
  Future<List<PistonShotIndex>> index({int? sinceMs, int limit = 128}) async {
    final rows = await _history({
      'dump_data': 'false',
      'sort': 'asc',
      'max_results': '$limit',
      if (sinceMs != null) 'start_date': '${sinceMs / 1000}',
    });
    return rows.map((r) {
      final id = r['id'];
      final time = pistonNumber(r['time']);
      if (id is! String || id.isEmpty || time == null || time < 0) {
        throw const FormatException('Invalid history identity');
      }
      return (id: id, timeMs: (time * 1000).round());
    }).toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  @override
  Future<List<PistonReading>> readings(List<String> ids) async {
    if (ids.isEmpty || ids.length > 10) {
      throw ArgumentError('History batch must contain 1–10 shots');
    }
    final rows = await _history({
      'ids': ids,
      'max_results': '${ids.length}',
      'dump_data': 'true',
    });
    if (rows.any((r) => r['data'] is! List || (r['data'] as List).isEmpty)) {
      throw const FormatException('Shot not fully available yet');
    }
    final result = await _analyzeHistory(rows);
    if (result.map((r) => r.shotId).toSet().length != ids.length ||
        !result.every((r) => ids.contains(r.shotId))) {
      throw const FormatException('Incomplete history batch');
    }
    return result;
  }

  @override
  void close() {
    _closed = true;
    _http.close(force: true);
  }
}

Future<Object?> _decodeHistory(List<int> bytes) =>
    Isolate.run(() => jsonDecode(utf8.decode(bytes)));

Future<List<PistonReading>> _analyzeHistory(List<Map<String, dynamic>> rows) =>
    Isolate.run(() => rows.map(analyzePiston).toList());
