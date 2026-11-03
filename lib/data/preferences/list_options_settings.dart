import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';
import 'package:holybeans/domain/list_options.dart';

/// Keeps the sort and display options of the Beans and Brews lists in the
/// preferences row.
class ListOptionsSettings {
  ListOptionsSettings(this.database);

  final AppDatabase database;

  Future<ListOptions> load() async {
    final saved = (await database.loadPreferences())?.listOptionsJson;
    if (saved == null) return const ListOptions();
    try {
      return ListOptions.fromJson(jsonDecode(saved));
    } on FormatException {
      return const ListOptions();
    }
  }

  Future<void> save(ListOptions options) => database.savePreferences(
    AppPreferencesCompanion(
      listOptionsJson: Value(jsonEncode(options.toJson())),
    ),
  );
}
