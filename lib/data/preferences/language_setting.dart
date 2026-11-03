import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart' show Locale;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';

/// The app language chosen in Settings, kept across launches.
class LanguageSetting {
  const LanguageSetting(this.database);

  final AppDatabase database;

  /// The saved language, or null to follow the device.
  Future<Locale?> load() async =>
      switch ((await database.loadPreferences())?.localeCode) {
        final code? => Locale(code),
        null => null,
      };

  Future<void> save(Locale? locale) => database.savePreferences(
    AppPreferencesCompanion(localeCode: Value(locale?.languageCode)),
  );
}
