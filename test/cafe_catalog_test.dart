import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';

class _Bundle extends Fake implements AssetBundle {
  _Bundle(this.read);
  final Future<String> Function() read;
  int loads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    expect(key, 'assets/catalogs/cafes.json');
    loads++;
    return read();
  }
}

String _catalog(String name) => jsonEncode({
  'venues': [
    {
      'name': name,
      'category': 'Coffee',
      'latitude': 40.5,
      'longitude': -3.25,
      'sourceKey': 'catalog:one',
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent and later opens share an immutable catalog', () async {
    final pending = Completer<String>();
    final bundle = _Bundle(() => pending.future);
    final opens = [
      for (var i = 0; i < 20; i++) CafeCatalog.load(bundle: bundle),
    ];
    expect(bundle.loads, 1);
    pending.complete(_catalog('Café'));
    final results = await Future.wait(opens);
    final entries = results.first;
    expect(results.every((result) => identical(result, entries)), true);
    expect(await CafeCatalog.load(bundle: bundle), same(entries));
    expect(bundle.loads, 1);
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.category, 'Coffee');
    expect(entry.venue.name, 'Café');
    expect(entry.venue.country, isNull);
    expect(entry.venue.city, isNull);
    expect(entry.venue.latitude, 40.5);
    expect(entry.venue.longitude, -3.25);
    expect(entry.venue.sourceKey, 'catalog:one');
    expect(entry.venue.sourceUrl, CafeCatalog.source);
    expect(entries.clear, throwsUnsupportedError);
  });

  test('a failed asset load can be retried', () async {
    var attempt = 0;
    final bundle = _Bundle(() async {
      if (++attempt == 1) throw StateError('Temporary asset failure');
      return _catalog('Recovered');
    });
    await expectLater(CafeCatalog.load(bundle: bundle), throwsStateError);
    final entries = await CafeCatalog.load(bundle: bundle);
    expect(entries.single.venue.name, 'Recovered');
    expect(await CafeCatalog.load(bundle: bundle), same(entries));
    expect(bundle.loads, 2);
  });

  test('a failed worker decode can be retried', () async {
    var attempt = 0;
    final bundle = _Bundle(
      () async => ++attempt == 1 ? 'broken JSON' : _catalog('Decoded'),
    );
    await expectLater(CafeCatalog.load(bundle: bundle), throwsFormatException);
    final entries = await CafeCatalog.load(bundle: bundle);
    expect(entries.single.venue.name, 'Decoded');
    expect(await CafeCatalog.load(bundle: bundle), same(entries));
    expect(bundle.loads, 2);
  });

  test('different asset bundles do not share catalog content', () async {
    final first = _Bundle(() async => _catalog('First'));
    final second = _Bundle(() async => _catalog('Second'));
    final a = await CafeCatalog.load(bundle: first);
    final b = await CafeCatalog.load(bundle: second);
    expect(a.single.venue.name, 'First');
    expect(b.single.venue.name, 'Second');
    expect(a, isNot(same(b)));
    expect(await CafeCatalog.load(bundle: first), same(a));
    expect(await CafeCatalog.load(bundle: second), same(b));
    expect(first.loads, 1);
    expect(second.loads, 1);
  });
}
