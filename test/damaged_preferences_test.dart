import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';

void main() {
  final validShare = ShareConfiguration(fields: {BrewParameter.notes}).toJson();
  final damagedShare = {
    'invalid JSON': '{',
    'unsupported version': jsonEncode({...validShare, 'version': 2}),
    'missing fields': '{"version":1}',
    'wrong field type': jsonEncode({
      ...validShare,
      'fields': [1],
    }),
    'wrong legacy field type': '[1]',
    'unknown default style': jsonEncode({
      ...validShare,
      'defaults': {'unknown': 'a'},
    }),
    'invalid template': jsonEncode({
      ...validShare,
      'templates': [<String, Object?>{}],
    }),
    'invalid label': jsonEncode({
      ...validShare,
      'labelTemplates': [<String, Object?>{}],
    }),
  };
  for (final entry in damagedShare.entries) {
    test(
      'share settings recover from ${entry.key} and remain writable',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.savePreferences(
          AppPreferencesCompanion(shareFieldsJson: Value(entry.value)),
        );
        final settings = ShareTemplateSettings(db);
        final recovered = await settings.load();
        expect(recovered.fields, defaultSharedParameters);
        expect(recovered.templates, isEmpty);
        expect(recovered.labelTemplates, isEmpty);
        expect(recovered.defaults, isEmpty);
        expect((await db.loadPreferences())!.shareFieldsJson, entry.value);
        await settings.saveFields({BrewParameter.notes});
        expect((await settings.load()).fields, {BrewParameter.notes});
        expect(
          ShareConfiguration.decode(
            (await db.loadPreferences())!.shareFieldsJson,
          ).fields,
          {BrewParameter.notes},
        );
      },
    );

    test(
      'restore rejects share ${entry.key} before replacing the journal',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final coffee = await JournalRepository(db)
            .createCoffee(name: 'Keep me', roaster: 'Test');
        await ShareTemplateSettings(db).saveFields({BrewParameter.notes});
        final preferences = (await db.loadPreferences())!.toJson();
        final backup = jsonDecode(
          await JournalBackup(db).exportJson(),
        ) as Map<String, dynamic>;
        backup['data']['preferences'][0]['shareFieldsJson'] = entry.value;
        backup['data']['coffees'][0]['name'] = 'Must not replace';
        final source = jsonEncode(backup);
        expect(
          () => JournalBackup.validate(source, (_) => true),
          throwsFormatException,
        );
        await expectLater(
          JournalBackup(db).restoreJson(source),
          throwsFormatException,
        );
        expect((await db.select(db.coffees).getSingle()).id, coffee);
        expect((await db.select(db.coffees).getSingle()).name, 'Keep me');
        expect((await db.loadPreferences())!.toJson(), preferences);
      },
    );
  }

  for (final source in [
    '{',
    '{}',
    '[{"id":"a"}]',
    '[{"id":"a","name":"A"},{"id":"a","name":"B"}]',
  ]) {
    for (final legacy in [false, true]) {
      test(
        'damaged scales $source recover with legacy=$legacy and remain writable',
        () async {
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);
          await db.savePreferences(
            AppPreferencesCompanion(
              scalesJson: Value(source),
              scaleDeviceId: Value(legacy ? 'old' : null),
              scaleName: Value(legacy ? 'Old scale' : null),
            ),
          );
          final settings = ScaleSettings(db);
          expect(
            (await settings.loadAll()).map((s) => s.deviceId),
            legacy ? ['old'] : isEmpty,
          );
          expect((await db.loadPreferences())!.scalesJson, source);
          await settings.save(
            const RememberedScale(deviceId: 'new', name: 'New scale'),
          );
          expect(
            (await settings.loadAll()).map((s) => s.deviceId),
            legacy ? ['new', 'old'] : ['new'],
          );
          await settings.forget('new');
          expect(
            (await settings.loadAll()).map((s) => s.deviceId),
            legacy ? ['old'] : isEmpty,
          );
        },
      );
    }
  }

  test(
    'a valid empty scale list takes precedence over the legacy pair',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.savePreferences(
        const AppPreferencesCompanion(
          scalesJson: Value('[]'),
          scaleDeviceId: Value('old'),
          scaleName: Value('Old scale'),
        ),
      );
      expect(await ScaleSettings(db).loadAll(), isEmpty);
    },
  );
}
