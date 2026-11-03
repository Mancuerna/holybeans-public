import 'package:drift/drift.dart' show Value;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/preferences_row.dart';

/// Remembers when the journal was last saved as a backup, to remind the
/// user when it has been a while.
class BackupSettings {
  BackupSettings(this.database);

  final AppDatabase database;

  Stream<DateTime?> watchLastBackup() => database.watchPreferences().map(
    (row) => switch (row?.lastBackupAtMs) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
      null => null,
    },
  );

  Future<void> markBackedUp(DateTime at) => database.savePreferences(
    AppPreferencesCompanion(
      lastBackupAtMs: Value(at.toUtc().millisecondsSinceEpoch),
    ),
  );
}
