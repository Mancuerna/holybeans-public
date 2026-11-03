import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/services/journal_backup.dart';

void main() {
  test('the chosen language is saved, kept with other settings and backed '
      'up', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final setting = LanguageSetting(database);
    expect(await setting.load(), isNull);

    await RateReminderSettings(database).saveMinutes(20);
    await setting.save(const Locale('es'));
    expect(await setting.load(), const Locale('es'));
    expect(await RateReminderSettings(database).loadMinutes(), 20);

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target)
        .restoreJson(await JournalBackup(database).exportJson());
    expect(await LanguageSetting(target).load(), const Locale('es'));

    await setting.save(null);
    expect(await setting.load(), isNull);
  });
}
