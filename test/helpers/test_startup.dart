import 'package:flutter/material.dart';
import 'package:holybeans/app/startup_services.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';

import 'fake_scale.dart';

class TestStartup extends StartupServices {
  TestStartup(this.database, this.photos, this.failure);

  final AppDatabase database;
  final PhotoStore photos;
  final String? failure;
  final started = <String>[];
  final workingScale = FakeScale();

  Future<T> attempt<T>(String name, T value) {
    started.add(name);
    if (name == failure) return Future.error(StateError('failed $name'));
    return Future.value(value);
  }

  @override
  bool get android => false;
  @override
  Future<bool> existingInstallation() => attempt('installation', false);
  @override
  Future<void> keepPreMigrationCopy() => attempt('safety copy', null);
  @override
  Future<AppDatabase> openDatabase() => attempt('database', database);
  @override
  Future<PhotoStore> openPhotos() => attempt('photos', photos);
  @override
  Future<void> recover(AppDatabase database, PhotoStore photos) =>
      attempt('recovery', null);
  @override
  Future<Locale?> loadLocale(AppDatabase database) =>
      attempt('language', const Locale('en'));
  @override
  Future<BackupServices?> backups() => attempt('backups', null);
  @override
  Future<(RateReminders, String?)?> reminders(
    ValueNotifier<String?> openRate,
  ) => attempt('reminders', null);
  @override
  Future<Scale?> scale(AppDatabase database) => attempt('scale', workingScale);
  @override
  Future<PressureSensor?> pressureSensor() => attempt('pressure', null);
  @override
  Future<Refractometer?> refractometer() => attempt('refractometer', null);
  @override
  Future<DriveSyncModel?> drive(AppDatabase database, PhotoStore photos) =>
      attempt('drive', null);
  @override
  Future<ReleaseNotesSettings?> releaseNotes(bool existing, String? launch) =>
      attempt('release notes', null);
}
