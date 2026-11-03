import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/loffee_bean.dart';

import 'helpers/fake_loffee.dart';

void main() {
  test('catalogue mapping keeps the bag and availability independent', () {
    final bean = LoffeeBean.fromJson(loffeeFixture);
    final card = bean.card;
    expect(
      (bean.id, card.name, card.roaster),
      ('42', 'Patrol Loffee Gesha', 'Test Roaster'),
    );
    expect(
      card.roastLevel,
      'light',
      reason: 'Omni is intended use, not roast degree',
    );
    expect(
      card.origins.single.country,
      'Spain',
      reason: 'not the roaster country',
    );
    expect(card.origins.single.producer, 'Test farm');
    expect(card.origins.single.farm, isNull);
    expect(card.flavorNotes, ['Jasmine', 'peach']);
    expect(card.roastDate, isNull);
    expect(card.priceCents, isNull);
    expect(card.bagGrams, isNull);
    expect(card.decaf, isFalse);
    expect(bean.elevation, '1200–1600 m');
    expect(card.origins.single.altitudeMeters, 1200);
    expect(card.origins.single.altitudeMaxMeters, 1600);
  });
  test('roast degrees map to our scale independently of recommended use', () {
    for (final entry in {
      'Ultra Light': 'ultra_light',
      'Light': 'light',
      'Medium': 'medium',
      'Dark': 'dark',
    }.entries) {
      expect(
        LoffeeBean.fromJson({...loffeeFixture, 'degree': entry.key})
            .card
            .roastLevel,
        entry.value,
      );
    }
    for (final entry in {
      'Nordic Light': 'ultra_light',
      'Medium-Light': 'omni',
      'Light To Medium': 'omni',
      'Medium-Dark': 'dark',
      'Nordic Light To Light': 'light',
      '  NORDIC   LIGHT TO LIGHT  ': 'light',
      'Medium – Light': 'omni',
    }.entries) {
      final bean = LoffeeBean.fromJson({
        ...loffeeFixture,
        'degree': entry.key,
        'type': 'Espresso',
      });
      expect(bean.card.roastLevel, entry.value);
      expect(bean.roastLevelIsApproximate, isTrue);
      expect(bean.roastDegree, entry.key.trim());
    }
    for (final degree in ['Unknown', 'Omni', 'Light To Dark', '', null]) {
      final bean = LoffeeBean.fromJson({...loffeeFixture, 'degree': degree});
      expect(bean.card.roastLevel, isNull);
      expect(bean.roastLevelIsApproximate, isFalse);
    }
  });
  test('an exact elevation maps; invalid ranges are not invented', () {
    final exact = LoffeeBean.fromJson({
      ...loffeeFixture,
      'min-elev': '1800',
      'max-elev': 1800,
    });
    expect(exact.card.origins.single.altitudeMeters, 1800);
    expect(exact.card.origins.single.altitudeMaxMeters, isNull);
    for (final values in [
      (-1, 1000),
      (2000, 1000),
      (double.nan, 1000),
      (10000, 10000),
    ]) {
      final bean = LoffeeBean.fromJson({
        ...loffeeFixture,
        'min-elev': values.$1,
        'max-elev': values.$2,
      });
      expect(bean.card.origins.single.altitudeMeters, isNull);
      expect(bean.elevation, isNull);
    }
  });
  test('free-tier missing fields and array tasting notes are accepted', () {
    final bean = LoffeeBean.fromJson({
      'roast-name': 'Minimal',
      'tasting': [' Peach ', null, 1, ''],
    });
    expect(bean.card.roaster, isEmpty);
    expect(bean.card.origins, isEmpty);
    expect(bean.description, isNull);
    expect(bean.imageUrl, isNull);
    expect(bean.card.flavorNotes, ['Peach']);
  });
  test('only safe HTTPS catalog links are offered', () {
    for (final url in [
      'http://example.com',
      'javascript:alert(1)',
      'https://key@host.example',
      '/relative',
    ]) {
      final bean = LoffeeBean.fromJson({
        ...loffeeFixture,
        'image': url,
        'link': url,
      });
      expect(bean.imageUrl, isNull);
      expect(bean.card.shopUrl, isNull);
    }
  });
  test('empty or malformed names are rejected', () {
    expect(
      () => LoffeeBean.fromJson({'roast-name': ' '}),
      throwsFormatException,
    );
  });
  test(
    'live response envelope and undocumented harvest numbers are handled',
    () {
      final page = LoffeePage.decode(
        {
          'meta': {
            'total': 1000,
            'page': 1,
            'limit': 20,
            'totalPages': 50,
            'tier': 'Free Access',
          },
          'beans': [
            {
              ...loffeeFixture,
              'degree': 'Nordic Light To Light',
              'harvest': '46023',
            },
          ],
        },
        page: 1,
        limit: 20,
      );
      expect(page.hasMore, isTrue);
      expect(page.beans.single.card.origins.single.harvest, isNull);
      expect(page.beans.single.harvestNeedsReview, isTrue);
      expect(page.beans.single.card.roastLevel, 'light');
      expect(page.beans.single.roastLevelIsApproximate, isTrue);
      expect(page.beans.single.roastDegree, 'Nordic Light To Light');
      expect(
        LoffeeBean.fromJson(loffeeFixture).card.origins.single.harvest,
        '2026',
      );
    },
  );
  test('supported page envelopes and pagination metadata', () {
    for (final payload in <Object?>[
      [loffeeFixture],
      {
        'data': [loffeeFixture],
      },
      {
        'beans': [loffeeFixture],
      },
      {
        'data': {
          'results': [loffeeFixture],
        },
      },
    ]) {
      expect(
        LoffeePage.decode(payload, page: 1, limit: 20).beans.single.id,
        '42',
      );
    }
    final total = LoffeePage.decode(
      {
        'data': [loffeeFixture],
        'meta': {'total': 21},
      },
      page: 1,
      limit: 20,
    );
    expect(total.hasMore, isTrue);
    final last = LoffeePage.decode(
      {
        'data': [loffeeFixture],
        'meta': {'total': 21},
      },
      page: 2,
      limit: 20,
    );
    expect(last.hasMore, isFalse);
    expect(LoffeePage.decode([], page: 1, limit: 20).hasMore, isFalse);
  });
  test('unrecognized response structures cannot masquerade as no results', () {
    for (final payload in <Object?>[
      {},
      {'error': 'failure'},
      {
        'data': [null],
      },
      {
        'data': [<String, Object?>{}],
      },
    ]) {
      expect(
        () => LoffeePage.decode(payload, page: 1, limit: 20),
        throwsFormatException,
      );
    }
  });
}
