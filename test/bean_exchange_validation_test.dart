import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/bean_exchange.dart';

void main() {
  test(
    'ambiguous or extreme amounts are dropped without changing their meaning',
    () {
      for (final value in [
        '12 euros + 3 shipping',
        '1e2',
        '1.234,56',
        '12-15',
        '£12',
        '12/kg',
        1e308,
      ]) {
        final read = readBeans(jsonEncode({'name': 'Lot', 'price': value}))
            .single;
        expect(read.bean.priceCents, isNull, reason: '$value');
        expect(read.dropped, contains('price'));
      }
      for (final value in ['1 kg', '100 + 50 g', '1e3', '250 ml']) {
        final read = readBeans(jsonEncode({'name': 'Lot', 'bagGrams': value}))
            .single;
        expect(read.bean.bagGrams, isNull, reason: value);
        expect(read.dropped, contains('bagGrams'));
      }
    },
  );

  test('plain decimal values and field-specific suffixes remain readable', () {
    for (final value in [
      18.5,
      '18.50',
      '18,50 €',
      '18.50 EUR',
      '18,50 euros',
    ]) {
      final read = readBeans(
        jsonEncode({'name': 'Lot', 'price': value, 'bagGrams': '250 g'}),
      ).single;
      expect(read.bean.priceCents, 1850);
      expect(read.bean.bagGrams, 250);
      expect(read.dropped, isEmpty);
    }
  });

  test('only exact real calendar dates are accepted', () {
    for (final date in [
      '2026-02-30',
      '2025-02-29',
      '2026-13-01',
      '2026-00-01',
      '2026-01-00',
      '2026-01-01T12:00:00Z',
      '0000-01-01',
    ]) {
      final read = readBeans(jsonEncode({'name': 'Lot', 'roastDate': date}))
          .single;
      expect(read.bean.roastDate, isNull, reason: date);
      expect(read.dropped, contains('roastDate'));
    }
    for (final date in ['2024-02-29', '2026-01-31']) {
      final read = readBeans(jsonEncode({'name': 'Lot', 'roastDate': date}))
          .single;
      expect(read.bean.roastDate, date);
      expect(read.dropped, isEmpty);
    }
  });

  test(
    'Markdown recovery preserves JSON escapes, literal slashes and Unicode',
    () {
      final read = readBeans(
        r'{"name":"Lot \*A\* \#1 \- 👩‍🌾 \\literal \"Q\" \u00e9","roastLevel":"ultra\_light","shopUrl":"https:\/\/example.com\/a\_b","flavorNotes":\["flower"\]}',
      ).single;
      expect(read.bean.name, 'Lot *A* #1 - 👩‍🌾 \\literal "Q" é');
      expect(read.bean.roastLevel, 'ultra_light');
      expect(read.bean.shopUrl, 'https://example.com/a_b');
      expect(read.bean.flavorNotes, ['flower']);
      expect(read.dropped, isEmpty);
      expect(
        () => readBeans(r'{"name":"Still invalid \q"}'),
        throwsA(isA<BeanReadException>()),
      );
    },
  );
}
