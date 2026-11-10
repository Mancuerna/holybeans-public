import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/meticulous_client.dart';

void main() {
  test(
    'accepts the size boundary and closes explicitly without new requests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final transport = _TrackedClient();
      addTearDown(() => transport.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.write('{"history":[]}'.padRight(16 * 1024 * 1024));
        await request.response.close();
      });
      final client = MeticulousClient(
        '127.0.0.1:${server.port}',
        httpClient: transport,
      );
      expect(await client.recentShots(), isEmpty);
      expect(transport.closed, isFalse);
      client.close();
      client.close();
      expect(transport.closed, isTrue);
      await expectLater(
        client.recentShots(),
        throwsA(isA<MeticulousException>()),
      );
      expect(requests, 1);
    },
  );

  for (final chunked in [false, true]) {
    test('rejects an oversized response with chunked=$chunked', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final transport = _TrackedClient();
      addTearDown(() => transport.close(force: true));
      final body = utf8.encode(
        jsonEncode({
          'history': <Object?>[],
          'padding': ' ' * (16 * 1024 * 1024),
        }),
      );
      server.listen((request) async {
        if (!chunked) request.response.contentLength = body.length;
        try {
          request.response.add(body);
          await request.response.close();
        } on SocketException {
          // The client may stop reading as soon as it sees the limit.
        }
      });
      final client = MeticulousClient(
        '127.0.0.1:${server.port}',
        httpClient: transport,
      );
      await expectLater(
        client.recentShots(),
        throwsA(isA<MeticulousException>()),
      );
      expect(transport.closed, isTrue);
    });
  }

  test('does not follow redirects away from the history endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final transport = _TrackedClient();
    addTearDown(() => transport.close(force: true));
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      if (paths.length == 1) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/other');
      } else {
        request.response.write('{"history":[]}');
      }
      await request.response.close();
    });
    final client = MeticulousClient(
      '127.0.0.1:${server.port}',
      httpClient: transport,
    );
    await expectLater(
      client.recentShots(),
      throwsA(isA<MeticulousException>()),
    );
    expect(paths, ['/api/v1/history']);
    expect(transport.closed, isTrue);
  });

  test('malformed optional text does not discard a valid shot', () {
    final shot = MeticulousShot.fromHistoryEntry({
      'id': 'shot',
      'time': 1000,
      'name': 42,
      'profile': {'name': 'Fallback', 'author': false},
      'data': [
        {
          'time': 0,
          'status': 42,
          'shot': {'weight': 0},
        },
        {
          'time': 1000,
          'status': 'Brew',
          'shot': {'weight': 5},
        },
      ],
    });
    expect(shot.profileName, 'Fallback');
    expect(shot.profileAuthor, isNull);
    expect(shot.yieldGrams, 5);
  });

  test('non-finite numeric strings are not accepted as measurements', () {
    final shot = MeticulousShot.fromHistoryEntry({
      'id': 'shot',
      'time': 1000,
      'profile': {'temperature': 'NaN', 'final_weight': 'Infinity'},
    });
    expect(shot.temperatureC, isNull);
    expect(shot.targetWeightGrams, isNull);
    expect(
      () => MeticulousShot.fromHistoryEntry({'id': 'shot', 'time': 'NaN'}),
      throwsFormatException,
    );
  });
}

class _TrackedClient implements HttpClient {
  final HttpClient _inner = HttpClient();
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(url);

  @override
  void close({bool force = false}) {
    closed = true;
    _inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
