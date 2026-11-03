import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';

/// Stores the reminder delay in the preferences row: minutes after an
/// unrated brew to remind the user to rate it, or null when off.
class RateReminderSettings {
  RateReminderSettings(this.database);

  final AppDatabase database;

  static const delays = [10, 20, 30, 60];

  Stream<int?> watchMinutes() =>
      database.watchPreferences().map((row) => row?.rateReminderMinutes);

  Future<int?> loadMinutes() async =>
      (await database.loadPreferences())?.rateReminderMinutes;

  Future<void> saveMinutes(int? minutes) async {
    if (minutes != null && minutes <= 0) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    await database.savePreferences(
      AppPreferencesCompanion(rateReminderMinutes: Value(minutes)),
    );
  }
}
