import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/bean_exchange.dart';

import 'helpers/escaped_bean_card.dart';

Coffee _coffee({int? priceCents, String? flavor}) => Coffee(
  id: 'c',
  name: 'Abu Coffee Geisha',
  roaster: 'Kima Coffee',
  paidPriceCents: priceCents,
  rating: 9,
  notes: 'Mine only',
  roastLevel: 'light',
  flavorProfile: flavor,
  isFavorite: true,
  isDecaf: false,
  shopUrl: 'https://kima.example/geisha',
  createdAtMs: 0,
  updatedAtMs: 0,
);

CoffeeLot _lot(String id, double grams, int createdAtMs) => CoffeeLot(
  id: id,
  coffeeId: 'c',
  initialGrams: grams,
  remainingGrams: 12,
  roastDate: '2026-09-25',
  createdAtMs: createdAtMs,
  updatedAtMs: createdAtMs,
);

CoffeeComponent _origin(int position, String country) => CoffeeComponent(
  id: 'o$position',
  coffeeId: 'c',
  position: position,
  country: country,
  region: 'Boquete',
  process: 'Natural',
  altitudeMeters: 1550,
);

void main() {
  test('recovers the tester card with Markdown escaped brackets', () {
    for (final text in [escapedBeanCard, '```json\n$escapedBeanCard\n```']) {
      final read = readBeans(text).single;
      expect(read.dropped, isEmpty);
      expect(read.bean.name, 'Hugo Pareja [SL9]');
      expect(read.bean.roaster, 'Rozali Coffee');
      expect(read.bean.origins.single.country, 'Perú');
      expect(read.bean.origins.single.altitudeMeters, 2205);
      expect(read.bean.flavorNotes, [
        'flores blancas',
        'bergamota',
        'albaricoque',
        'ciruela amarilla',
      ]);
      expect(read.bean.priceCents, 2500);
      expect(read.bean.bagGrams, 100);
      expect(
        read.bean.shopUrl,
        'https://rozalicoffee.com/products/hugo-pareja-sl9',
      );
    }
  });

  test('bracket recovery preserves valid JSON escape pairs', () {
    const name = r'Lot \\[literal] \"quoted\" \u00e9';
    for (final brackets in [('[', ']'), (r'\[', r'\]')]) {
      final text = '{"beans": ${brackets.$1}{"name":"$name"}${brackets.$2}}';
      expect(readBeans(text).single.bean.name, r'Lot \[literal] "quoted" é');
    }
    expect(
      () => readBeans(r'{"name":"Invalid \q", "origins":\[\]}'),
      throwsA(isA<BeanReadException>()),
    );
  });

  test('a coffee becomes a card without anything personal', () {
    final bean = SharedBean.fromCoffee(
      _coffee(priceCents: 2400, flavor: 'Mango, raspberry'),
      [_origin(1, 'Colombia'), _origin(0, 'Panama')],
      [_lot('old', 250, 1), _lot('new', 500, 2)],
    );
    // 24 € paid for 750 g: the latest 500 g bag's share is 16 €.
    expect((bean.bagGrams, bean.priceCents), (500, 1600));
    expect(bean.roastDate, isNull, reason: 'the receiver has their own bag');
    expect(bean.origins.map((o) => o.country), ['Panama', 'Colombia']);
    expect(bean.flavorNotes, ['Mango', 'raspberry']);
    final json = bean.toJson();
    expect(json.keys, isNot(contains('rating')));
    expect(json.keys, isNot(contains('notes')));
  });

  test('files and QR codes read back what they carried', () {
    final bean = SharedBean.fromCoffee(
      _coffee(priceCents: 796, flavor: 'Mango, raspberry, blueberry'),
      [_origin(0, 'Panama')],
      [_lot('bag', 50, 1)],
    );
    for (final text in [
      encodeBeans([bean]),
      beanQrText(bean),
    ]) {
      final read = readBeans(text).single;
      expect(read.dropped, isEmpty);
      expect(read.bean.toJson(), bean.toJson());
    }
    expect(beanQrText(bean), startsWith(beanQrPrefix));
    expect(beanQrText(bean).length, lessThan(600));
  });

  test('an AI answer is read leniently and nothing is guessed', () {
    const answer = '''
Here are your coffees:
```json
[
  {
    "name": "Inmaculada Pink Bourbon",
    "roaster": "Guido Coffee",
    "country": "Colombia",
    "region": "Valle del Cauca",
    "variety": "Pink Bourbon",
    "altitudeMeters": "2000 m",
    "roastLevel": "Light",
    "decaf": "no",
    "flavorNotes": "Strawberry, rose",
    "price": "18,50 €",
    "bagGrams": "200 g",
    "roastDate": "last week",
    "shopUrl": "guido coffee shop"
  },
  {"roaster": "No name, skipped"},
  {"name": "Mystery", "roastLevel": "cinnamon", "price": -3}
]
```
Enjoy!''';
    final [pink, mystery] = readBeans(answer);
    final bean = pink.bean;
    expect(bean.origins.single.country, 'Colombia');
    expect(bean.origins.single.altitudeMeters, 2000);
    expect(bean.roastLevel, 'light');
    expect(bean.decaf, isFalse);
    expect(bean.flavorNotes, ['Strawberry', 'rose']);
    expect((bean.priceCents, bean.bagGrams), (1850, 200));
    expect(pink.dropped, unorderedEquals(['roastDate', 'shopUrl']));
    expect(mystery.bean.roaster, '', reason: 'the form will ask for it');
    expect(mystery.dropped, unorderedEquals(['roastLevel', 'price']));
  });

  test('nothing to read says why', () {
    BeanReadError error(String text) {
      try {
        readBeans(text);
      } on BeanReadException catch (exception) {
        return exception.error;
      }
      fail('read $text');
    }

    expect(
      error('Sorry, I could not open those links.'),
      BeanReadError.notJson,
    );
    expect(error('{"beans": []}'), BeanReadError.noBeans);
    expect(error('[{"roaster": "Only"}]'), BeanReadError.noBeans);
    expect(
      error('{"format": "holybeans-beans", "version": 99, "beans": []}'),
      BeanReadError.newerVersion,
    );
    expect(error('${beanQrPrefix}not-gzip'), BeanReadError.notJson);
  });

  test('a card matches the coffee already in the journal', () {
    final coffees = [_coffee()];
    expect(
      existingCoffee(
        const SharedBean(name: ' abu coffee  GEISHA', roaster: 'kima coffee'),
        coffees,
      )?.id,
      'c',
    );
    expect(
      existingCoffee(
        const SharedBean(name: 'Abu Coffee Geisha', roaster: 'Other'),
        coffees,
      ),
      isNull,
    );
  });

  test('a card survives what copying and pasting does to it', () {
    final clean = encodeBeans([
      const SharedBean(
        name: 'Syoum Family',
        roaster: 'Paso Paso',
        flavorNotes: ['Crème Brûlée'],
      ),
    ]);
    for (final dirty in [
      clean.replaceAll('  ', '\u00A0\u00A0'),
      '\uFEFF\u200B$clean',
      clean.replaceAllMapped(
        RegExp(r'"([^"]*)"'),
        (match) => '\u201C${match[1]}\u201D',
      ),
      clean.replaceAll('\n', '\r\n'),
      // What a Samsung received from a computer: soft line breaks.
      clean.replaceAll('\n', '\u000B'),
      clean.replaceAll('\n', '\u2028'),
    ]) {
      expect(readBeans(dirty).single.bean.name, 'Syoum Family');
    }
    try {
      readBeans('{"beans": [{"name": "Broken",}');
      fail('read broken JSON');
    } on BeanReadException catch (exception) {
      expect(exception.detail, isNotNull);
    }
  });
}
