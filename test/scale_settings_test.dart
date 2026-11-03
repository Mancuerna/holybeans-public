import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/journal_backup.dart';

void main() {
  test('the paired scale is remembered, backed up and forgotten', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final settings = ScaleSettings(database);
    expect(await settings.load(), isNull);

    await settings.save(
      const RememberedScale(deviceId: 'EA:54:62:00:00:09', name: 'BOOKOO_SC_U'),
    );
    final backup = await JournalBackup(database).exportJson();
    expect(backup, contains('"version":${JournalBackup.version}'));

    await settings.save(null);
    expect(await settings.load(), isNull);

    await JournalBackup(database).restoreJson(backup);
    final restored = (await settings.load())!;
    expect(restored.deviceId, 'EA:54:62:00:00:09');
    expect(restored.name, 'BOOKOO_SC_U');
  });
  test(
    'legacy pair survives and several scales round trip in priority order',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.savePreferences(
        const AppPreferencesCompanion(
          scaleDeviceId: Value('ultra'),
          scaleName: Value('BOOKOO_SC_U'),
        ),
      );
      final settings = ScaleSettings(db);
      expect((await settings.loadAll()).single.deviceId, 'ultra');
      await settings.save(
        const RememberedScale(deviceId: 'mini', name: 'BOOKOO_SC_M'),
      );
      await settings.save(
        const RememberedScale(deviceId: 'ultra', name: 'BOOKOO_SC_U'),
      );
      final backup = await JournalBackup(db).exportJson();
      await settings.save(null);
      await JournalBackup(db).restoreJson(backup);
      expect((await settings.loadAll()).map((s) => s.deviceId), [
        'ultra',
        'mini',
      ]);
      await settings.forget('ultra');
      expect((await settings.load())!.deviceId, 'mini');
      await settings.forget('mini');
      expect(await settings.loadAll(), isEmpty);
      expect((await db.loadPreferences())!.scaleDeviceId, isNull);
    },
  );

  test(
    'invalid or duplicate saved identities reject restoration atomically',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = ScaleSettings(db);
      await settings.save(
        const RememberedScale(deviceId: 'ultra', name: 'BOOKOO_SC_U'),
      );
      final original = await JournalBackup(db).exportJson();
      for (final invalid in [
        '{}',
        '[{"id":"a"}]',
        '[{"id":"a","name":"A"},{"id":"a","name":"B"}]',
      ]) {
        final backup = jsonDecode(original) as Map<String, dynamic>;
        backup['data']['preferences'][0]['scalesJson'] = invalid;
        await expectLater(
          JournalBackup(db).restoreJson(jsonEncode(backup)),
          throwsFormatException,
        );
        expect((await settings.load())!.deviceId, 'ultra');
      }
    },
  );
}
