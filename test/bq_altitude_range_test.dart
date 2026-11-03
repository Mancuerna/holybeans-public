import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';

import 'helpers/beanconqueror_fixture.dart' as fixture;

void main() {
  test(
    'BeanConqueror import and refresh preserve both elevation endpoints',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final payload = fixture.exportJson();
      final origin =
          (payload['BEANS'] as List).first['bean_information'][0] as Map;
      origin['elevation'] = '1111 - 1456 m';
      Future<void> import() async {
        final archive = BeanconquerorArchive.read(
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        );
        await repo.importBeanconqueror(
          planBeanconquerorImport(archive, await repo.beanconquerorJournal()),
        );
      }

      await import();
      var component = await db.select(db.coffeeComponents).getSingle();
      final coffeeId = component.coffeeId;
      expect(
        (component.altitudeMeters, component.altitudeMaxMeters),
        (1111, 1456),
      );
      origin['elevation'] = '1222–1666 m';
      await import();
      component = await db.select(db.coffeeComponents).getSingle();
      expect(component.coffeeId, coffeeId);
      expect(
        (component.altitudeMeters, component.altitudeMaxMeters),
        (1222, 1666),
      );
      expect(await db.select(db.coffees).get(), hasLength(2));
    },
  );
}
