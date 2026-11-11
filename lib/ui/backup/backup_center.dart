import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_settings.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/services/backup_coordinator.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/pre_migration.dart';

export 'package:holybeans/data/services/backup_coordinator.dart'
    show BackupServices;

/// Notifies the backup UI and forwards app lifecycle to the backup service.
class BackupCenter extends ChangeNotifier with WidgetsBindingObserver {
  BackupCenter({
    required AppDatabase database,
    required PhotoStore? photos,
    BackupServices? services,
    DateTime Function()? clock,
  }) {
    _coordinator = BackupCoordinator(
      database: database,
      photos: photos,
      services: services,
      clock: clock,
      onChanged: notifyListeners,
    );
  }
  late final BackupCoordinator _coordinator;
  AppDatabase get database => _coordinator.database;
  PhotoStore? get photos => _coordinator.photos;
  BackupServices? get services => _coordinator.services;
  JournalBackup get backup => _coordinator.backup;
  BackupSettings get settings => _coordinator.settings;
  DateTime? get lastBackup => _coordinator.lastBackup;
  bool get lastBackupKnown => _coordinator.lastBackupKnown;
  BackupState get state => _coordinator.state;
  set state(BackupState value) => _coordinator.state = value;
  bool? get folderAvailable => _coordinator.folderAvailable;
  List<AutoBackupEntry> get autoEntries => _coordinator.autoEntries;
  List<PreMigrationCopy> get preMigrationEntries =>
      _coordinator.preMigrationEntries;
  bool get savingToFolder => _coordinator.savingToFolder;
  bool get hasAutoBackups => _coordinator.hasAutoBackups;
  bool get canUseFolder => _coordinator.canUseFolder;
  bool get hasFolder => canUseFolder && state.folderUri != null;
  bool get monthlyReminderOpen => _coordinator.monthlyReminderOpen;
  bool get folderReminderDue => _coordinator.folderReminderDue;
  bool get folderLost => _coordinator.folderLost;
  void start() {
    _coordinator.start();
    if (services != null) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(check());
  }

  Future<void> check({bool force = false}) => _coordinator.check(force: force);
  Future<void> beforeRestore() => _coordinator.beforeRestore();
  void dismissMonthlyReminder() => _coordinator.dismissMonthlyReminder();
  Future<void> refreshFolder() => _coordinator.refreshFolder();
  Future<bool> chooseFolder() => _coordinator.chooseFolder();
  Future<void> forgetFolder() => _coordinator.forgetFolder();
  Future<void> saveToFolder() => _coordinator.saveToFolder();
  Future<void> dismissFolderReminder() => _coordinator.dismissFolderReminder();
  @override
  void dispose() {
    if (services != null) WidgetsBinding.instance.removeObserver(this);
    _coordinator.dispose();
    super.dispose();
  }
}
