import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
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
  static final _loads = Expando<Future<List<CafeCatalogEntry>>>();

  static Future<List<CafeCatalogEntry>> load({AssetBundle? bundle}) {
    final assets = bundle ?? rootBundle;
    return _loads[assets] ??= _load(assets);
  }

  static Future<List<CafeCatalogEntry>> _load(AssetBundle assets) async {
    try {
      final text = await assets.loadString('assets/catalogs/cafes.json');
      return await compute(_decode, text);
    } catch (_) {
      // A temporary load failure must not poison subsequent picker opens.
      _loads[assets] = null;
      rethrow;
    }
  }

  static List<CafeCatalogEntry> _decode(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return List.unmodifiable([
      for (final raw in json['venues'] as List<dynamic>)
        _entry(raw as Map<String, dynamic>),
    ]);
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
