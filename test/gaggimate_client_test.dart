import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';

import 'helpers/gaggimate_fixture.dart';

void main() {
  test(
    'normalizes hosts and rejects paths, credentials and unsafe schemes',
    () {
      expect(
        GaggimateClient.normalizeAddress(' GAGGIMATE.local/ ').toString(),
        'http://gaggimate.local',
      );
      for (final address in [
        '',
        'ftp://x',
        'http://u:p@x',
        'http://x/api/scales/tare',
        'http://x?q=1',
      ]) {
        expect(() => GaggimateClient(address), throwsFormatException);
      }
    },
  );
  test(
    'reads only history GET files, optional notes and weighed shot',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri}');
        switch (request.uri.path) {
          case '/api/history/index.bin':
            request.response.add(gaggimateIndex());
          case '/api/history/000031.slog':
            request.response.add(gaggimateLog());
          case '/api/history/000031.json':
          case '/api/history/31.json':
            request.response.statusCode = 404;
          default:
            request.response.statusCode = 500;
        }
        await request.response.close();
      });
      final client = GaggimateClient('127.0.0.1:${server.port}');
      addTearDown(client.close);
      final shot = await client.shot((await client.history()).single);
      expect(shot.yieldGrams, 36.5);
      expect(requests, [
        'GET /api/history/index.bin',
        'GET /api/history/000031.slog',
        'GET /api/history/000031.json',
        'GET /api/history/31.json',
      ]);
      expect(
        () => client.shot(
          GaggimateHistoryEntry(
            id: '../control',
            brewedAt: DateTime(2026),
            profileName: '',
            durationMs: 1,
          ),
        ),
        throwsA(isA<GaggimateException>()),
      );
      expect(requests.length, 4);
    },
  );
  for (final legacyNotes in [false, true]) {
    test(
      'missing optional notes served as HTML do not reject a valid shot (legacy=$legacyNotes)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requests = <String>[];
        server.listen((request) async {
          requests.add('${request.method} ${request.uri}');
          switch (request.uri.path) {
            case '/api/history/index.bin':
              request.response.add(gaggimateIndex());
            case '/api/history/000031.slog':
              request.response.add(gaggimateLog(version: 7));
            case '/api/history/31.json' when legacyNotes:
              request.response.headers.contentType = ContentType.json;
              request.response.write('{"doseIn":"18.5","notes":"Sweet"}');
            default:
              request.response.headers.contentType = ContentType.html;
              request.response.write(
                '<!doctype html><html><body>Gaggimate</body></html>',
              );
          }
          await request.response.close();
        });
        final client = GaggimateClient('127.0.0.1:${server.port}');
        addTearDown(client.close);
        final shot = await client.shot((await client.history()).single);
        expect(shot.yieldGrams, 36.5);
        expect(shot.curve!.timesMs, [0, 4000, 8000, 30000, 32000]);
        expect(shot.doseGrams, legacyNotes ? 18.5 : null);
        expect(shot.notes, legacyNotes ? 'Sweet' : null);
        expect(requests, [
          'GET /api/history/index.bin',
          'GET /api/history/000031.slog',
          'GET /api/history/000031.json',
          'GET /api/history/31.json',
        ]);
      },
    );
  }
  for (final status in [302, 404, 503]) {
    test(
      'HTTP $status reports unavailability without following redirects',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var count = 0;
        server.listen((request) async {
          count++;
          request.response.statusCode = status;
          request.response.headers.set('location', '/api/scales/tare');
          await request.response.close();
        });
        final client = GaggimateClient('127.0.0.1:${server.port}');
        addTearDown(client.close);
        expect(
          client.history(),
          throwsA(
            isA<GaggimateException>().having(
              (e) => e.failure,
              'failure',
              GaggimateFailure.unavailable,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(count, 1);
      },
    );
  }
}
