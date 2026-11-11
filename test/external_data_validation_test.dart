import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/domain/share_template.dart';

void main() {
  test('backup fingerprint rejects malformed root and data containers', () {
    for (final value in <Object?>[
      null,
      [],
      1,
      {},
      {'data': null},
      {'data': <Object?>[]},
      {'data': 'journal'},
    ]) {
      expect(() => journalDigest(jsonEncode(value)), throwsFormatException);
    }
    expect(journalDigest('{"data":{}}').empty, isTrue);
  });

  test('piston analysis rejects a non-list data field', () {
    for (final data in <Object>[{}, 1, 'samples']) {
      expect(
        () => analyzePiston({'id': 'shot', 'time': 1, 'data': data}),
        throwsFormatException,
      );
    }
    for (final data in <Object?>[null, []]) {
      expect(analyzePiston({'id': 'shot', 'time': 1, 'data': data}).samples, 0);
    }
  });

  const template = {
    'id': 'template',
    'name': 'Coffee',
    'style': 'filter',
    'body': '<coffee>',
  };
  test('template decoding validates contents', () {
    for (final changed in <Map<String, Object?>>[
      {'id': ''},
      {'name': ' '},
      {'name': 'x' * 81},
      {'body': ' '},
      {'body': 'x' * 8001},
      {'body': '<unknown>'},
    ]) {
      expect(
        () => ShareTemplate.fromJson({...template, ...changed}),
        throwsFormatException,
      );
    }
    expect(ShareTemplate.fromJson(template).toJson(), template);
  });
  test('template decoding normalizes malformed field errors', () {
    for (final changed in <Map<String, Object?>>[
      {'id': null},
      {'name': 1},
      {'style': 'unknown'},
      {'style': []},
      {'body': false},
    ]) {
      expect(
        () => ShareTemplate.fromJson({...template, ...changed}),
        throwsFormatException,
      );
    }
  });

  test('catalog page keeps valid rows and paginates using raw row count', () {
    final page = LoffeePage.decode(
      [
        {'roast-name': 'First'},
        null,
        {'roast-name': ''},
        {'roast-name': 'Last'},
      ],
      page: 1,
      limit: 4,
    );
    expect(page.beans.map((bean) => bean.card.name), ['First', 'Last']);
    expect(page.hasMore, isTrue);
    expect(
      () => LoffeePage.decode([null, <String, Object?>{}], page: 1, limit: 2),
      throwsFormatException,
    );
  });

  test(
    'bean envelopes cannot bypass version checks with non-integer values',
    () {
      for (final version in <Object?>['999', 999.5, null, false, {}]) {
        expect(
          () => readBeans(
            jsonEncode({
              'version': version,
              'beans': [
                {'name': 'Coffee'},
              ],
            }),
          ),
          throwsA(isA<BeanReadException>()),
        );
      }
      expect(readBeans('{"name":"Coffee"}').single.bean.name, 'Coffee');
      expect(
        readBeans(encodeBeans([const SharedBean(name: 'Coffee', roaster: '')]))
            .single
            .bean
            .name,
        'Coffee',
      );
    },
  );

  for (final url in [
    'http://example.com/coffee',
    'https:///coffee',
    'https://key@host.example/coffee',
    'javascript:alert(1)',
    '/relative',
  ]) {
    test('shared bean drops unsafe shop URL $url', () {
      final read = readBeans(jsonEncode({'name': 'Coffee', 'shopUrl': url}))
          .single;
      expect(read.bean.shopUrl, isNull);
      expect(read.dropped, contains('shopUrl'));
    });
    test('BeanConqueror drops unsafe shop URL $url', () {
      expect(_coffee({'url': url}).shopUrl, isNull);
    });
  }
  test('all coffee imports retain a valid HTTPS shop link', () {
    const url = 'https://example.com/coffee?size=250#details';
    expect(
      readBeans(jsonEncode({'name': 'Coffee', 'shopUrl': url}))
          .single
          .bean
          .shopUrl,
      url,
    );
    expect(_coffee({'url': url}).shopUrl, url);
    expect(
      LoffeeBean.fromJson({'roast-name': 'Coffee', 'link': url}).card.shopUrl,
      url,
    );
  });

  test(
    'frozen pause counts calendar days across daylight saving boundaries',
    () {
      for (final dates in [
        ('2026-03-29', '2026-03-30', 1),
        ('2026-03-28', '2026-03-30', 2),
        ('2026-10-25', '2026-10-26', 1),
        ('2026-03-29', '2026-03-29', null),
        ('2026-03-30', '2026-03-29', null),
      ]) {
        expect(
          _coffee({'frozenDate': dates.$1, 'unfrozenDate': dates.$2})
              .lot
              .frozenPauseDays,
          dates.$3,
          reason: '${dates.$1} to ${dates.$2}',
        );
      }
    },
  );
}

PlannedCoffee _coffee(Map<String, Object?> fields) => planBeanconquerorImport(
  BqExport(
    beans: [
      {
        'config': {'uuid': 'bean'},
        'name': 'Coffee',
        'weight': 100,
        ...fields,
      },
    ],
  ),
  const BqJournal(),
  now: DateTime.utc(2026),
).coffees.single;
