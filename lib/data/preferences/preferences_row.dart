import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_parameters.dart';

/// The app keeps its preferences in a single row (id 1) of
/// `app_preferences`. Each setting class reads and writes its own columns
/// through these helpers.
extension PreferencesRow on AppDatabase {
  SimpleSelectStatement<$AppPreferencesTable, AppPreference> _preferences() =>
      select(appPreferences)..where((row) => row.id.equals(1));

  /// The row, or null before any preference was saved.
  Future<AppPreference?> loadPreferences() => _preferences().getSingleOrNull();

  Stream<AppPreference?> watchPreferences() =>
      _preferences().watchSingleOrNull();

  /// Writes [changes], creating the row with its defaults first. Columns
  /// not in [changes] keep their values.
  Future<void> savePreferences(AppPreferencesCompanion changes) =>
      writeGate.withPreferencesLock(() async {
        await into(appPreferences).insert(
          changes.copyWith(
            id: const Value(1),
            shareFieldsJson: changes.shareFieldsJson.present
                ? changes.shareFieldsJson
                : Value(
                    jsonEncode(encodeSharedParameters(defaultSharedParameters)),
                  ),
          ),
          onConflict: DoUpdate((_) => changes),
        );
      });
}
