import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/backup_folder.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';

class StartupServices {
  const StartupServices();

  bool get android => defaultTargetPlatform == TargetPlatform.android;

  Future<bool> existingInstallation() async =>
      (await AppDatabase.file()).existsSync();

  Future<void> keepPreMigrationCopy() async {
    await (await PreMigrationCopies.open()).keepIfUpgrading(
      await AppDatabase.file(),
      currentSchema: AppDatabase.currentSchema,
    );
  }

  Future<AppDatabase> openDatabase() async {
    final database = await AppDatabase.open();
    try {
      // Drift opens SQLite and applies migrations on the first query.
      await database.customSelect('SELECT 1').get();
      return database;
    } catch (_) {
      await optionalStartup(database.close);
      rethrow;
    }
  }

  Future<PhotoStore> openPhotos() => PhotoStore.open();
  Future<void> recover(AppDatabase database, PhotoStore photos) =>
      JournalRestore(JournalBackup(database), photos).recover();
  Future<Locale?> loadLocale(AppDatabase database) =>
      LanguageSetting(database).load();

  Future<BackupServices?> backups() =>
      BackupServices.open(folder: android ? const AndroidBackupFolder() : null);

  Future<(RateReminders, String?)?> reminders(
    ValueNotifier<String?> openRate,
  ) => LocalRateReminders.start(onOpen: (id) => openRate.value = id);

  Future<Scale?> scale(AppDatabase database) async =>
      android ? _load<BleScale>(BleScale(ScaleSettings(database))) : null;

  Future<PressureSensor?> pressureSensor() async => android
      ? _load<BlePressureSensor>(
          BlePressureSensor(await BlePressureSensor.openStore()),
        )
      : null;

  Future<Refractometer?> refractometer() async => android
      ? _load<BleRefractometer>(
          BleRefractometer(await BleRefractometer.openStore()),
        )
      : null;

  Future<T> _load<T extends BleLink<Object>>(T device) async {
    try {
      await device.load();
      return device;
    } catch (_) {
      device.dispose();
      rethrow;
    }
  }

  Future<DriveSyncModel?> drive(
    AppDatabase database,
    PhotoStore photos,
  ) async =>
      android ? DriveSyncModel.open(JournalBackup(database), photos) : null;

  Future<ReleaseNotesSettings?> releaseNotes(
    bool existingInstallation,
    String? launchBrew,
  ) async {
    final settings = await ReleaseNotesSettings.open();
    return await settings.pending(existingInstallation: existingInstallation) &&
            launchBrew == null
        ? settings
        : null;
  }
}

Future<T?> optionalStartup<T>(Future<T> Function() start) async {
  try {
    return await start();
  } catch (error, stack) {
    reportError(error, stack);
    return null;
  }
}
