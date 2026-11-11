import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/backup_coordinator.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';

/// Stable dependencies shared by app routes, sheets and their controllers.
/// The creators retain ownership; the scope does not open or close services.
class AppServices {
  AppServices({
    required this.database,
    JournalRepository? repository,
    BrewParameterSettings? parameterSettings,
    ShareTemplateSettings? templateSettings,
    RateReminderSettings? reminderSettings,
    this.photos,
    this.reminders,
    this.openRate,
    this.scale,
    this.pressureSensor,
    this.refractometer,
    this.exportFolder,
    this.incoming,
    this.loffee,
    this.backupServices,
    this.driveSync,
    this.releaseNotes,
  }) : repository = repository ?? JournalRepository(database),
       parameterSettings = parameterSettings ?? BrewParameterSettings(database),
       templateSettings = templateSettings ?? ShareTemplateSettings(database),
       reminderSettings = reminderSettings ?? RateReminderSettings(database);

  factory AppServices.forJournal(
    JournalRepository repository, {
    required BrewParameterSettings parameterSettings,
    PhotoStore? photos,
    Scale? scale,
    PressureSensor? pressureSensor,
    Refractometer? refractometer,
  }) => AppServices(
    database: repository.database,
    repository: repository,
    parameterSettings: parameterSettings,
    photos: photos,
    scale: scale,
    pressureSensor: pressureSensor,
    refractometer: refractometer,
  );

  factory AppServices.forPreferences(
    BrewParameterSettings parameterSettings, {
    required ShareTemplateSettings templateSettings,
    RateReminderSettings? reminderSettings,
    RateReminders? reminders,
    Scale? scale,
    PressureSensor? pressureSensor,
    Refractometer? refractometer,
  }) => AppServices(
    database: parameterSettings.database,
    parameterSettings: parameterSettings,
    templateSettings: templateSettings,
    reminderSettings: reminderSettings,
    reminders: reminders,
    scale: scale,
    pressureSensor: pressureSensor,
    refractometer: refractometer,
  );

  final AppDatabase database;
  final JournalRepository repository;
  final BrewParameterSettings parameterSettings;
  final ShareTemplateSettings templateSettings;
  final RateReminderSettings reminderSettings;
  final PhotoStore? photos;
  final RateReminders? reminders;
  final ValueNotifier<String?>? openRate;
  final Scale? scale;
  final PressureSensor? pressureSensor;
  final Refractometer? refractometer;
  final ExportFolder? exportFolder;
  final IncomingShares? incoming;
  final LoffeeServices? loffee;
  final BackupServices? backupServices;
  final DriveSyncModel? driveSync;
  final ReleaseNotesSettings? releaseNotes;
}

/// Makes one dependency bundle available above the navigator.
class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    super.key,
    required this.services,
    required super.child,
  });
  final AppServices services;

  /// Non-listening access, also usable while a controller initializes.
  static AppServices read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppServicesScope>();
    if (element == null) {
      throw StateError('No AppServicesScope in this context');
    }
    return (element.widget as AppServicesScope).services;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      services != oldWidget.services;
}
