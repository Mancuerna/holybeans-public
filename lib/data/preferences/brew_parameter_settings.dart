import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/domain/brew_parameters.dart';

/// Which brew parameters show and which are shared, both kept in the single
/// preferences row (`hidden_brew_fields_json` and `share_fields_json`).
class BrewParameterSettings {
  BrewParameterSettings(this.database);

  final AppDatabase database;

  Stream<Set<BrewParameter>> watchHidden() => database.watchPreferences().map(
    (row) => _hidden(row?.hiddenBrewFieldsJson),
  );

  Future<Set<BrewParameter>> loadHidden() async =>
      _hidden((await database.loadPreferences())?.hiddenBrewFieldsJson);

  Stream<Set<BrewParameter>> watchShared() =>
      database.watchPreferences().map((row) => _shared(row?.shareFieldsJson));

  Future<Set<BrewParameter>> loadShared() async =>
      _shared((await database.loadPreferences())?.shareFieldsJson);

  Future<void> saveHidden(Set<BrewParameter> hidden) {
    final json = jsonEncode([
      for (final parameter in BrewParameter.values)
        if (parameter.canHide && hidden.contains(parameter)) parameter.name,
    ]);
    return database.savePreferences(
      AppPreferencesCompanion(hiddenBrewFieldsJson: Value(json)),
    );
  }

  /// Saves the shared parameters; at least one is required.
  Future<void> saveShared(Set<BrewParameter> shared) async {
    if (!shared.any((parameter) => parameter.canShare)) {
      throw ArgumentError.value(shared, 'shared');
    }
    await ShareTemplateSettings(database).saveFields(shared);
  }

  static Set<BrewParameter> _hidden(String? source) {
    if (source == null) return {};
    try {
      return decodeHiddenParameters(
        (jsonDecode(source) as List).whereType<String>(),
      );
    } catch (_) {
      return {};
    }
  }

  static Set<BrewParameter> _shared(String? source) {
    if (source == null) return {...defaultSharedParameters};
    try {
      return ShareConfiguration.decode(source).fields;
    } catch (_) {
      return {...defaultSharedParameters};
    }
  }
}
