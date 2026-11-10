@Tags(['slow'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

import 'helpers/legacy_schema.dart';

void main() {
  for (var from = 19; from < AppDatabase.currentSchema; from++) {
    test(
      'schema $from migrates to the current schema without changing old rows',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'holybeans-schema-test-',
        );
        final file = File('${directory.path}/journal.sqlite');
        var db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final repo = JournalRepository(db);
          final coffee = await repo.createCoffee(
            name: 'Existing diary',
            roaster: 'Test',
            initialGrams: 250,
            altitudeMeters: 1850,
          );
          final lot = (await repo.coffeeLots(coffee)).single;
          final method = await repo.createMethod(name: 'V60');
          final tool = await repo.createMethodTool(
            methodId: method,
            name: 'Paper',
          );
          await repo.createBrew(
            coffeeId: coffee,
            lotId: lot.id,
            methodName: 'V60',
            methodId: method,
            methodToolIds: [tool],
            doseGrams: 18,
            waterGrams: 270,
            bloomSeconds: 45,
          );
          final saved = (await db.select(db.brews).getSingle()).toJson();
          await reconstructLegacySchema(db, from);
          await db.close();
          db = AppDatabase.forTesting(NativeDatabase(file));
          expect((await db.select(db.brews).getSingle()).toJson(), saved);
          expect(
            (await db.select(db.coffeeLots).getSingle()).remainingGrams,
            232,
          );
          final origin = await db.select(db.coffeeComponents).getSingle();
          expect(origin.altitudeMeters, 1850);
          expect(origin.altitudeMaxMeters, isNull);
          final columns = await db
              .customSelect('PRAGMA table_info(app_preferences)')
              .get();
          expect(
            columns.map((r) => r.read<String>('name')),
            containsAll(['scale_device_id', 'scale_name']),
          );
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single,
            AppDatabase.currentSchema,
          );
          expect((await db.select(db.methodTools).getSingle()).id, tool);
          // Since 22 a tool belongs to its methods through links only.
          expect(
            (await db.select(db.methodTools).getSingle()).methodId,
            from < 22 ? method : null,
          );
          expect(
            await JournalRepository(db).brewToolIds(saved['id'] as String),
            [tool],
          );
          expect(
            (await db.select(db.toolMethodLinks).getSingle()).methodId,
            method,
          );
          expect(
            (await db.customSelect('PRAGMA quick_check').getSingle())
                .data
                .values
                .single,
            'ok',
          );
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        } finally {
          await db.close();
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  test('a newer schema is rejected without changing its version', () async {
    final directory = await Directory.systemTemp.createTemp(
      'holybeans-downgrade-test-',
    );
    final file = File('${directory.path}/journal.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await db.customStatement(
        'PRAGMA user_version = ${AppDatabase.currentSchema + 1}',
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      await expectLater(
        db.select(db.brews).get(),
        throwsA(isA<UnsupportedError>()),
      );
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
