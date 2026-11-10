import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/app/startup_services.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/loffee_key_store.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/rate_reminders.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/device_toasts.dart';
import 'package:holybeans/ui/core/release_notes.dart';
import 'package:holybeans/ui/shell/journal_shell.dart';
import 'package:holybeans/ui/startup/startup_recovery.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_page.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';

/// Licences and attribution for assets and adapted third-party code.
Stream<LicenseEntry> bundledAppLicenses() async* {
  yield LicenseEntryWithLineBreaks(const [
    'Noto Emoji',
  ], await rootBundle.loadString('assets/licenses/noto-emoji.txt'));
  yield LicenseEntryWithLineBreaks(const [
    'IBM Plex Sans',
  ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  yield LicenseEntryWithLineBreaks(const [
    'aioacaia protocol reference',
  ], await rootBundle.loadString('assets/licenses/aioacaia.txt'));
  yield LicenseEntryWithLineBreaks(const [
    'NiimBlueLib protocol reference',
  ], await rootBundle.loadString('assets/licenses/niimbluelib.txt'));
  yield LicenseEntryWithLineBreaks([
    'Meticulous piston analysis',
  ], await rootBundle.loadString('assets/licenses/meticulous-piston.txt'));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorReporting();
  LicenseRegistry.addLicense(bundledAppLicenses);
  runApp(await prepareApp());
}

Future<Widget> prepareApp({
  StartupServices services = const StartupServices(),
}) async {
  AppDatabase? opened;
  late final AppDatabase database;
  late final PhotoStore photos;
  late final bool existingInstallation;
  try {
    existingInstallation = await services.existingInstallation();
    await optionalStartup(services.keepPreMigrationCopy);
    database = opened = await services.openDatabase();
    photos = await services.openPhotos();
    await services.recover(database, photos);
  } catch (error, stack) {
    reportError(error, stack);
    if (opened != null) await optionalStartup(opened.close);
    return StartupRecoveryApp(error: error);
  }
  final openRate = ValueNotifier<String?>(null);
  final android = services.android;
  final backupsReady = optionalStartup(services.backups);
  final remindersReady = optionalStartup(() => services.reminders(openRate));
  final locale = await optionalStartup(() => services.loadLocale(database));
  final (reminders, launchBrew) = await remindersReady ?? (null, null);
  openRate.value = launchBrew;
  final backupServices = await backupsReady;
  final scale = await optionalStartup(() => services.scale(database));
  final pressureSensor = await optionalStartup(services.pressureSensor);
  final refractometer = await optionalStartup(services.refractometer);
  final driveSync = await optionalStartup(
    () => services.drive(database, photos),
  );
  final releaseNotes = await optionalStartup(
    () => services.releaseNotes(existingInstallation, launchBrew),
  );
  return HolyBeansApp(
    database: database,
    initialLocale: locale,
    photos: photos,
    reminders: reminders,
    openRate: openRate,
    scale: scale,
    pressureSensor: pressureSensor,
    refractometer: refractometer,
    exportFolder: android ? const AndroidExportFolder() : null,
    incoming: android ? IncomingShares() : null,
    loffee: android
        ? LoffeeServices(
            api: LoffeeClient(),
            keys: const AndroidLoffeeKeyStore(),
          )
        : null,
    backupServices: backupServices,
    driveSync: driveSync,
    releaseNotes: releaseNotes,
  );
}

class HolyBeansApp extends StatefulWidget {
  const HolyBeansApp({
    super.key,
    required this.database,
    this.initialLocale,
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
  });

  final AppDatabase database;
  final DriveSyncModel? driveSync;
  final ReleaseNotesSettings? releaseNotes;

  /// Coffee cards opened, shared or scanned into the app; without it
  /// (tests) nothing arrives from outside.
  final IncomingShares? incoming;
  final LoffeeServices? loffee;

  /// Automatic and folder copies; without them (tests) they are hidden.
  final BackupServices? backupServices;

  /// Bluetooth scale; without it the scale controls are hidden.
  final Scale? scale;

  /// Bluetooth pressure sensor; without it its controls are hidden.
  final PressureSensor? pressureSensor;

  /// Bluetooth refractometer; without it the TDS has no measure button.
  final Refractometer? refractometer;

  /// Reads another app's export folder; without it imports take a file.
  final ExportFolder? exportFolder;

  /// Photo folder; without it the app hides photo controls (e.g. in tests).
  final PhotoStore? photos;

  /// Rating reminders; without them the reminder setting is hidden.
  final RateReminders? reminders;

  /// Brew IDs whose reminder was tapped, to open their rate sheet.
  final ValueNotifier<String?>? openRate;
  final Locale? initialLocale;

  @override
  State<HolyBeansApp> createState() => _HolyBeansAppState();
}

class _HolyBeansAppState extends State<HolyBeansApp>
    with WidgetsBindingObserver {
  Locale? locale;
  late final releaseNotes = widget.releaseNotes == null
      ? null
      : ReleaseNotesObserver(widget.releaseNotes!);

  /// How often the app looks again for paired devices that are not
  /// connected, while it is on screen.
  static const _retryEvery = Duration(seconds: 8);
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    locale = widget.initialLocale;
    WidgetsBinding.instance.addObserver(this);
    _reconnectDevices();
    widget.driveSync?.lifecycle(AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _retry?.cancel();
    widget.driveSync?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.driveSync?.lifecycle(state);
    if (state == AppLifecycleState.resumed) {
      _reconnectDevices();
    } else {
      _retry?.cancel();
      _retry = null;
    }
  }

  /// Paired Bluetooth devices connect by themselves when the app opens or
  /// comes back and, while it is on screen, whenever they are switched on
  /// again: the app keeps trying every few seconds. Connected ones, ones
  /// the user disconnected and a denied permission are left alone.
  void _reconnectDevices() {
    for (final device in <PairedDevice?>[
      widget.scale,
      widget.pressureSensor,
      widget.refractometer,
    ]) {
      if (device == null || device.status == DeviceStatus.denied) continue;
      unawaited(device.connect(automatic: true));
    }
    _retry ??= Timer.periodic(_retryEvery, (_) => _reconnectDevices());
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    navigatorObservers: [
      if (widget.driveSync != null) widget.driveSync!.observer,
      ?releaseNotes,
    ],
    // Above every screen and sheet: the devices connecting by themselves.
    builder: (context, child) {
      return DeviceToasts(
        devices: {
          DeviceKind.scale: ?widget.scale,
          DeviceKind.pressureSensor: ?widget.pressureSensor,
          DeviceKind.refractometer: ?widget.refractometer,
        },
        child: widget.driveSync == null
            ? child!
            : DriveSyncScope(
                model: widget.driveSync!,
                child: DriveSyncNotice(model: widget.driveSync!, child: child!),
              ),
      );
    },
    home: JournalShell(
      database: widget.database,
      photos: widget.photos,
      reminders: widget.reminders,
      openRate: widget.openRate,
      scale: widget.scale,
      pressureSensor: widget.pressureSensor,
      refractometer: widget.refractometer,
      exportFolder: widget.exportFolder,
      incoming: widget.incoming,
      loffee: widget.loffee,
      backupServices: widget.backupServices,
      driveTile: widget.driveSync == null
          ? null
          : DriveSyncTile(model: widget.driveSync!),
      locale: locale,
      onLocaleChanged: (value) {
        setState(() => locale = value);
        LanguageSetting(widget.database).save(value);
      },
    ),
  );
}
