import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:holybeans/domain/cafe_journal.dart';

class CafeCatalogEntry {
  const CafeCatalogEntry(this.venue, this.category);
  final CafeInput venue;
  final String category;
}

class CafeCatalog {
  static const source =
      'https://coffeeandtranslation.com/pages/mapa-cafe-especialidad';
  static Future<List<CafeCatalogEntry>> load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/catalogs/cafes.json'),
    ) as Map<String, dynamic>;
    return [
      for (final raw in json['venues'] as List<dynamic>)
        _entry(raw as Map<String, dynamic>),
    ];
  }

  static CafeCatalogEntry _entry(Map<String, dynamic> row) => CafeCatalogEntry(
    CafeInput(
      name: row['name'] as String,
      country: row['country'] as String?,
      city: row['city'] as String?,
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      sourceKey: row['sourceKey'] as String,
      sourceUrl: source,
    ),
    row['category'] as String,
  );
}
