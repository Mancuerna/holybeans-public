import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';

import 'helpers/test_database.dart';

void main() {
  test('explicit single elevations and ranges preserve their endpoints', () {
    for (final entry in <Object, (int, int?)>{
      1800: (1800, null),
      '1800 m': (1800, null),
      '1.800 msnm': (1800, null),
      '1111  - 1456 m': (1111, 1456),
      '1,800–2,000 masl': (1800, 2000),
      '1800 to 2000': (1800, 2000),
      '1800 a 2000 m': (1800, 2000),
      '1800–1800 m': (1800, null),
    }.entries) {
      expect(parseAltitude(entry.key), entry.value);
    }
    for (final value in [
      null,
      -1,
      0,
      double.nan,
      1.5,
      'high',
      '-1800',
      '2000-1800 m',
      '0-1800 m',
      '1800-2000-2200 m',
    ]) {
      expect(parseAltitude(value), isNull, reason: '$value');
    }
    expect(bqAltitudeMax('1800-2000 m'), 2000);
    expect(bqAltitudeMax('2000-1800 m'), isNull);
    expect(bqAltitudeMax('10000-11000 m'), isNull);
    expect(altitudeLabel(1111, 1456), '1111–1456 m');
    expect(altitudeLabel(1800, null), '1800 m');
    expect(altitudeLabel(1800, 1800), '1800 m');
  });

  test(
    'cards and QR preserve ranges and still accept the old single field',
    () {
      const card = SharedBean(
        name: 'Altitude',
        roaster: 'Test',
        origins: [
          SharedOrigin(
            country: 'Spain',
            altitudeMeters: 1111,
            altitudeMaxMeters: 1456,
          ),
        ],
      );
      for (final text in [
        encodeBeans([card]),
        beanQrText(card),
      ]) {
        final read = readBeans(text).single;
        expect(read.dropped, isEmpty);
        expect(read.bean.toJson(), card.toJson());
      }
      for (final input in [
        {'altitudeMeters': '1111 - 1456 m'},
        {'altitudeMeters': 1111, 'altitudeMaxMeters': '1456'},
      ]) {
        final origin = readBeans(
          jsonEncode({
            'name': 'Test',
            'origins': [input],
          }),
        ).single.bean.origins.single;
        expect((origin.altitudeMeters, origin.altitudeMaxMeters), (1111, 1456));
      }
      final old = readBeans('{"name":"Old","altitudeMeters":1800}').single;
      expect(old.bean.origins.single.altitudeMeters, 1800);
      expect(old.bean.origins.single.altitudeMaxMeters, isNull);
      final invalid = readBeans(
        '{"name":"Wrong","altitudeMeters":2000,"altitudeMaxMeters":1800}',
      ).single;
      expect(invalid.dropped, contains('altitudeMeters'));
      expect(invalid.bean.origins.single.altitudeMaxMeters, isNull);
    },
  );

  test(
    'editing and backups preserve both endpoints without changing origin IDs',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(
        name: 'Range',
        roaster: 'Test',
        altitudeMeters: 1111,
        altitudeMaxMeters: 1456,
      );
      final original = (await repo.coffeeComponents(id)).single;
      await repo.updateCoffeeProfileWithComponents(
        id: id,
        name: 'Range',
        roaster: 'Test',
        paidPriceCents: null,
        components: [
          CoffeeComponentInput(
            id: original.id,
            altitudeMeters: 1200,
            altitudeMaxMeters: 1600,
          ),
        ],
      );
      final updated = (await repo.coffeeComponents(id)).single;
      expect(updated.id, original.id);
      expect((updated.altitudeMeters, updated.altitudeMaxMeters), (1200, 1600));
      final backup = JournalBackup(db);
      final source = await backup.exportJson();
      expect(jsonDecode(source)['version'], JournalBackup.version);
      await backup.restoreJson(source);
      expect((await repo.coffeeComponents(id)).single, updated);
      final old = jsonDecode(source) as Map<String, dynamic>;
      old['version'] = 19;
      for (final component in old['data']['components'] as List) {
        (component as Map).remove('altitudeMaxMeters');
      }
      await backup.restoreJson(jsonEncode(old));
      final restored = (await repo.coffeeComponents(id)).single;
      expect(restored.altitudeMeters, 1200);
      expect(restored.altitudeMaxMeters, isNull);
    },
  );

  test(
    'reversed and orphan upper endpoints fail without altering a journal',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final id = await repo.createCoffee(
        name: 'Single',
        roaster: 'Test',
        altitudeMeters: 1800,
      );
      for (final pair in [(2000, 1800), (null, 1800), (-1, 1800)]) {
        await expectLater(
          repo.createCoffee(
            name: 'Invalid',
            roaster: 'Test',
            altitudeMeters: pair.$1,
            altitudeMaxMeters: pair.$2,
          ),
          throwsArgumentError,
        );
      }
      final backup = JournalBackup(db);
      final payload =
          jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
      (payload['data']['components'] as List).single['altitudeMaxMeters'] =
          1600;
      await expectLater(
        backup.restoreJson(jsonEncode(payload)),
        throwsFormatException,
      );
      expect(await db.select(db.coffees).get(), hasLength(1));
      expect((await repo.coffeeComponents(id)).single.altitudeMeters, 1800);
    },
  );
}
