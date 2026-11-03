import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/piston_history_client.dart';

import 'piston_analysis_test.dart' show sample;

void main() {
  test(
    'only GET machine/history, with incremental index and repeated IDs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      server.listen((r) async {
        expect(r.method, 'GET');
        requests.add(r.uri);
        final Object body;
        if (r.uri.path == '/api/v1/machine') {
          body = {'serial': 'test-serial'};
        } else if (r.uri.queryParameters['dump_data'] == 'false') {
          body = {
            'history': [
              {'id': 'one', 'time': 1000},
              {'id': 'two', 'time': 1001},
            ],
          };
        } else {
          expect(r.uri.queryParametersAll['ids'], ['one', 'two']);
          body = {
            'history': [
              for (final id in ['one', 'two'])
                {
                  'id': id,
                  'time': 1000,
                  'data': [
                    sample(status: 'Extraction'),
                    for (var i = 0; i < 5; i++) sample(),
                  ],
                },
            ],
          };
        }
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      final client = PistonHistoryClient('http://127.0.0.1:${server.port}');
      try {
        expect(await client.serial(), 'test-serial');
        expect(await client.index(sinceMs: 999000), hasLength(2));
        expect(
          (await client.readings(['one', 'two'])).every((r) => r.usable),
          true,
        );
        expect(requests[1].queryParameters['start_date'], '999.0');
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );
  for (final redirect in [true, false]) {
    test(
      redirect
          ? 'rejects redirects without following them'
          : 'rejects missing requested shots',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var count = 0;
        server.listen((r) async {
          count++;
          if (redirect) {
            r.response.statusCode = 302;
            r.response.headers.set('location', '/other');
          } else {
            r.response.write('{"history":[]}');
          }
          await r.response.close();
        });
        final client = PistonHistoryClient('http://127.0.0.1:${server.port}');
        try {
          await expectLater(
            client.readings(['missing']),
            throwsA(isA<Exception>()),
          );
          expect(count, 1);
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  }
}
