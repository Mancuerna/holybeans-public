import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/cafe_catalog.dart';

import 'support/audit_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('repeated offline catalog opens retain all venue fields', () async {
    final source = jsonDecode(
      await rootBundle.loadString('assets/catalogs/cafes.json'),
    ) as Map<String, dynamic>;
    final rows = (source['venues'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    List<CafeCatalogEntry>? previous;
    var materializations = 0;
    var calls = 0;
    final measurement = await measure(() async {
      for (var i = 0; i < 20; i++) {
        final entries = await CafeCatalog.load();
        calls++;
        if (!identical(entries, previous)) materializations++;
        previous = entries;
      }
    });
    final entries = previous!;
    expect(entries, hasLength(rows.length));
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final entry = entries[i];
      final venue = entry.venue;
      expect(
        (
          venue.name,
          venue.country,
          venue.city,
          venue.latitude,
          venue.longitude,
          venue.sourceKey,
          entry.category,
        ),
        (
          row['name'],
          row['country'],
          row['city'],
          row['latitude'],
          row['longitude'],
          row['sourceKey'],
          row['category'],
        ),
      );
      expect(venue.sourceUrl, CafeCatalog.source);
    }
    stdout.writeln(
      'CAFE_CATALOG ${jsonEncode({'environment': 'host Flutter test; warmed bundled asset string', 'venues': rows.length, 'loadsPerSample': 20, 'callsIncludingWarmups': calls, 'materializedListsIncludingWarmups': materializations, ...measurement})}',
    );
  });
}
