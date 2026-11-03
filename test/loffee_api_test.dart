import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/loffee_api.dart';

import 'helpers/fake_loffee.dart';

void main() {
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late LoffeeClient client;
  final requests = <HttpRequest>[];
  late void Function(HttpRequest) respond;
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [loffeeFixture],
        }),
      );
      unawaited(request.response.close());
    };
    subscription = server.listen((request) {
      requests.add(request);
      respond(request);
    });
    client = LoffeeClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/api/v2/beans'),
      interval: const Duration(milliseconds: 80),
    );
  });
  tearDown(() async {
    await subscription.cancel();
    await server.close(force: true);
  });
  Matcher failure(LoffeeFailure expected) => throwsA(
    isA<LoffeeException>().having((e) => e.failure, 'failure', expected),
  );

  test(
    'GET has Bearer auth, encoded search and pagination, no key in URL',
    () async {
      final result = await client.search(
        key: 'test-only-key',
        query: 'Gesha & España',
        page: 2,
      );
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.headers.value('authorization'), 'Bearer test-only-key');
      expect(request.uri.queryParameters, {
        'search': 'Gesha & España',
        'page': '2',
        'limit': '20',
      });
      expect(request.uri.toString(), isNot(contains('test-only-key')));
      expect(result.beans.single.card.name, 'Patrol Loffee Gesha');
    },
  );
  test(
    'cache avoids requests but is not reused with another credential',
    () async {
      await client.search(key: 'first-test-key', query: 'Gesha');
      await client.search(key: 'first-test-key', query: 'Gesha');
      expect(requests, hasLength(1));
      await client.search(key: 'other-test-key', query: 'Gesha');
      expect(requests, hasLength(2));
    },
  );
  test('concurrent searches are spaced apart', () async {
    final arrivals = <DateTime>[];
    respond = (request) {
      arrivals.add(DateTime.now());
      request.response.write('[]');
      unawaited(request.response.close());
    };
    await Future.wait([
      client.search(key: 'test-key', query: 'one'),
      client.search(key: 'test-key', query: 'two'),
    ]);
    expect(
      arrivals.last.difference(arrivals.first).inMilliseconds,
      greaterThanOrEqualTo(60),
    );
  });
  test('401 and 403 are sanitized credential failures', () async {
    for (final code in [401, 403]) {
      respond = (request) {
        request.response.statusCode = code;
        request.response.write('echo-test-key');
        unawaited(request.response.close());
      };
      await expectLater(
        client.search(key: 'test-key', query: '$code'),
        failure(LoffeeFailure.authentication),
      );
    }
  });
  test(
    'a slow response still leaves the full interval before the next GET',
    () async {
      final arrivals = <DateTime>[];
      respond = (request) {
        arrivals.add(DateTime.now());
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 150), () async {
            request.response.write('[]');
            await request.response.close();
          }),
        );
      };
      await Future.wait([
        client.search(key: 'test-key', query: 'slow first'),
        client.search(key: 'test-key', query: 'second'),
      ]);
      expect(
        arrivals.last.difference(arrivals.first).inMilliseconds,
        greaterThanOrEqualTo(210),
      );
    },
  );
  test('429 honors Retry-After without blocking indefinitely', () async {
    respond = (request) {
      request.response.statusCode = 429;
      request.response.headers.set('retry-after', '3600');
      unawaited(request.response.close());
    };
    await expectLater(
      client.search(key: 'test-key', query: 'first'),
      failure(LoffeeFailure.rateLimit),
    );
    await expectLater(
      client.search(key: 'test-key', query: 'second'),
      failure(LoffeeFailure.rateLimit),
    );
    expect(requests, hasLength(1));
  });
  test('redirects never forward the credential', () async {
    respond = (request) {
      request.response.statusCode = 302;
      request.response.headers.set(
        'location',
        'http://127.0.0.1:${server.port}/foreign',
      );
      unawaited(request.response.close());
    };
    await expectLater(
      client.search(key: 'test-key', query: 'redirect'),
      failure(LoffeeFailure.unavailable),
    );
    expect(requests, hasLength(1));
  });
  test(
    'replacing a rate-limited key does not inherit its quota wait',
    () async {
      respond = (request) {
        if (request.headers.value('authorization') == 'Bearer old-test-key') {
          request.response.statusCode = 429;
          request.response.headers.set('retry-after', '3600');
        } else {
          request.response.write('[]');
        }
        unawaited(request.response.close());
      };
      await expectLater(
        client.search(key: 'old-test-key', query: 'Gesha'),
        failure(LoffeeFailure.rateLimit),
      );
      expect(
        (await client.search(key: 'new-test-key', query: 'Gesha')).beans,
        isEmpty,
      );
      expect(requests, hasLength(2));
    },
  );
  test(
    'invalid JSON and oversized responses give a recoverable response error',
    () async {
      respond = (request) {
        request.response.write('not json');
        unawaited(request.response.close());
      };
      await expectLater(
        client.search(key: 'test-key', query: 'bad'),
        failure(LoffeeFailure.response),
      );
      respond = (request) {
        request.response.write('x' * (3 * 1024 * 1024));
        unawaited(request.response.close().catchError((Object _) {}));
      };
      await expectLater(
        client.search(key: 'test-key', query: 'large'),
        failure(LoffeeFailure.response),
      );
    },
  );
  test('timeout is a network error', () async {
    respond = (_) {};
    client = LoffeeClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/api/v2/beans'),
      timeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      client.search(key: 'test-key', query: 'slow'),
      failure(LoffeeFailure.network),
    );
  });
  test('invalid credential input never reaches HTTP', () async {
    for (final key in ['', 'test\nkey', 'test key']) {
      await expectLater(
        client.search(key: key, query: 'Gesha'),
        failure(LoffeeFailure.authentication),
      );
    }
    expect(requests, isEmpty);
  });
  test('untrusted photo URL schemes are rejected', () async {
    await expectLater(
      client.photo('http://example.com/photo'),
      failure(LoffeeFailure.response),
    );
    expect(requests, isEmpty);
  });
}
