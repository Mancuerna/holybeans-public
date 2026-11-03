import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_settings.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/backup_folder.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:holybeans/ui/core/error_report.dart';

/// Phone services for automatic and folder copies. Without them (tests,
/// other platforms) only the manual backup and its monthly reminder remain.
class BackupServices {
  const BackupServices({
    required this.autoBackups,
    required this.state,
    this.folder,
    this.preMigration,
  });

  final AutoBackups autoBackups;
  final BackupStateStore state;

  /// The journal as it was before updates that changed its schema.
  final PreMigrationCopies? preMigration;

  /// The chosen folder for daily copies; null where there is none.
  final BackupFolder? folder;

  static Future<BackupServices> open({BackupFolder? folder}) async =>
      BackupServices(
        autoBackups: await AutoBackups.open(),
        state: await BackupStateStore.open(),
        folder: folder,
        preMigration: await PreMigrationCopies.open(),
      );
}

/// Everything about keeping the journal safe that Home and Settings share:
/// the monthly reminder, automatic copies inside the app and the daily copy
/// to a chosen folder. Owned by the shell.
///
/// Automatic copies are taken when the app goes to the background after the
/// journal changed, so exporting never slows the screen in use.
class BackupCenter extends ChangeNotifier with WidgetsBindingObserver {
  BackupCenter({
    required this.database,
    required this.photos,
    this.services,
    DateTime Function()? clock,
  }) : backup = JournalBackup(database),
       settings = BackupSettings(database),
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final PhotoStore? photos;
  final BackupServices? services;
  final JournalBackup backup;
  final BackupSettings settings;
  final DateTime Function() _clock;

  StreamSubscription<DateTime?>? _lastBackupSubscription;
  StreamSubscription<Object?>? _changes;
  Future<void>? _checking;
  Future<void> _folderWork = Future.value();

  Future<T> _withFolder<T>(Future<T> Function() action) {
    final next = _folderWork.then((_) => action());
    _folderWork = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Saved state read at start; every change waits for it, so a late read
  /// never overwrites a newer choice.
  Future<void> _ready = Future.value();
  bool _dirty = true;
  bool _disposed = false;

  /// When the journal was last saved outside the app; null if never.
  DateTime? lastBackup;
  bool lastBackupKnown = false;
  bool _monthlyDismissed = false;

  BackupState state = const BackupState();

  /// Whether the chosen folder can still be written; null until checked.
  bool? folderAvailable;
  List<AutoBackupEntry> autoEntries = const [];

  /// Copies kept before updates that changed the journal's schema.
  List<PreMigrationCopy> preMigrationEntries = const [];

  /// A daily copy is being written to the folder.
  bool savingToFolder = false;

  bool get hasAutoBackups => services != null;
  bool get canUseFolder => services?.folder != null;
  bool get hasFolder => canUseFolder && state.folderUri != null;

  void start() {
    _lastBackupSubscription = settings.watchLastBackup().listen((at) {
      lastBackup = at;
      lastBackupKnown = true;
      _notify();
    });
    if (services == null) return;
    WidgetsBinding.instance.addObserver(this);
    _changes = backup.watchChanges().listen((_) => _dirty = true);
    _ready = _load();
    unawaited(_ready.then((_) => refreshFolder()));
  }

  Future<void> _load() async {
    try {
      state = await services!.state.load();
      autoEntries = await services!.autoBackups.list();
      preMigrationEntries =
          await services!.preMigration?.list() ?? const <PreMigrationCopy>[];
      _notify();
    } catch (error, stack) {
      reportError(error, stack);
      // Backups must never stop the journal from opening.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(check());
  }

  /// Fingerprints a changed journal and saves an automatic copy when one is
  /// due. [force] skips the daily interval, as before a restore.
  Future<void> check({bool force = false}) {
    if (services == null) return Future.value();
    final running = _checking;
    if (running != null) {
      return force ? running.then((_) => check(force: true)) : running;
    }
    return _checking = _check(force).whenComplete(() => _checking = null);
  }

  Future<void> _check(bool force) async {
    await _ready;
    if (!_dirty && !force && state.journalFingerprint != null) return;
    try {
      _dirty = false;
      final snapshot = await JournalSnapshot.take(backup);
      state = state.withJournal(snapshot.fingerprint, empty: snapshot.empty);
      await services!.state.save(state);
      await services!.autoBackups.saveIfNeeded(
        snapshot,
        now: _clock(),
        force: force,
      );
      autoEntries = await services!.autoBackups.list();
      _notify();
    } catch (error, stack) {
      reportError(error, stack);
      _dirty = true;
      if (force) rethrow;
    }
  }

  /// Saves the journal as it is now before a restore replaces it, so the
  /// restore can be undone from the automatic copies.
  Future<void> beforeRestore() => check(force: true);

  // Monthly reminder, for journals without a chosen folder.

  bool get monthlyReminderOpen =>
      lastBackupKnown && !_monthlyDismissed && !hasFolder;

  void dismissMonthlyReminder() {
    _monthlyDismissed = true;
    _notify();
  }

  // Daily copy to the chosen folder.

  bool get folderReminderDue =>
      hasFolder &&
      folderAvailable == true &&
      !savingToFolder &&
      folderBackupDue(
        journalFingerprint: state.journalFingerprint,
        journalEmpty: state.journalEmpty,
        lastFolderFingerprint: state.folderFingerprint,
        lastFolderDay: switch (state.folderSavedAt) {
          final at? => localDay(at),
          null => null,
        },
        dismissedDay: state.folderDismissedDay,
        now: _clock(),
      );

  /// The folder was chosen but can no longer be written; Home warns once a
  /// day, like the daily reminder.
  bool get folderLost =>
      hasFolder &&
      folderAvailable == false &&
      state.folderDismissedDay != localDay(_clock());

  Future<void> refreshFolder() async {
    await _ready;
    final uri = state.folderUri;
    final folder = services?.folder;
    if (uri == null || folder == null) return;
    try {
      final available = await folder.isAvailable(uri);
      if (state.folderUri != uri) return;
      folderAvailable = available;
    } catch (error, stack) {
      reportError(error, stack);
      if (state.folderUri != uri) return;
      folderAvailable = false;
    }
    _notify();
  }

  /// Lets the user pick the folder, then saves the first copy there.
  /// Returns false when cancelled; throws when the copy failed.
  Future<bool> chooseFolder() => _withFolder(_chooseFolder);

  Future<bool> _chooseFolder() async {
    await _ready;
    final folder = services!.folder!;
    final picked = await folder.pick();
    if (picked == null) return false;
    final previous = state.folderUri;
    if (previous != null && previous != picked.uri) {
      await folder.release(previous).catchError((_) {});
    }
    state = state.withFolder(picked.uri, picked.name);
    folderAvailable = true;
    await services!.state.save(state);
    _notify();
    await _saveToFolder();
    return true;
  }

  Future<void> forgetFolder() => _withFolder(_forgetFolder);

  Future<void> _forgetFolder() async {
    await _ready;
    final uri = state.folderUri;
    if (uri == null) return;
    await services!.folder!.release(uri).catchError((_) {});
    state = state.withoutFolder();
    folderAvailable = null;
    await services!.state.save(state);
    _notify();
  }

  /// Saves today's full copy, photos included, to the chosen folder.
  Future<void> saveToFolder() => _withFolder(_saveToFolder);

  Future<void> _saveToFolder() async {
    await _ready;
    final uri = state.folderUri!;
    savingToFolder = true;
    _notify();
    try {
      final (snapshot, pictures) = await JournalSnapshot.takeWithPhotos(
        backup,
        photos,
      );
      final source = snapshot.source;
      final bytes = await Isolate.run(
        () => JournalBackup.encodeArchive(source, pictures),
      );
      final now = _clock();
      await services!.folder!.save(uri, bytes, now);
      state = state.withFolderCopy(now, snapshot.fingerprint);
      folderAvailable = true;
      await services!.state.save(state);
      await settings.markBackedUp(now);
    } catch (error, stack) {
      reportError(error, stack);
      await refreshFolder();
      rethrow;
    } finally {
      savingToFolder = false;
      _notify();
    }
  }

  /// Puts the daily reminder off until tomorrow.
  Future<void> dismissFolderReminder() async {
    await _ready;
    state = state.withDismissed(localDay(_clock()));
    _notify();
    await services?.state.save(state);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (services != null) WidgetsBinding.instance.removeObserver(this);
    _lastBackupSubscription?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}
