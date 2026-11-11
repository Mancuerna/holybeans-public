import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_failure.dart';
import 'package:holybeans/data/services/drive_storage.dart';
import 'package:holybeans/data/services/drive_sync_contracts.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';

// The existing name and config path preserve installed users' Google opt-in.
class DriveSyncModel extends ChangeNotifier {
  DriveSyncModel._(
    this.backup,
    this.photos,
    this.storage,
    this.deviceId,
    this.account,
    this.enabled,
    this.connectTimeout,
  ) {
    observer = NavigatorObserver();
    // Drive availability must never control the ability to save the diary.
    backup.database.writeGate.writable = true;
    _changes = backup.watchChanges().listen((_) {
      _revision++;
      _dirty = true;
      // A save marks work pending but does not start network activity.
      if (!busy && enabled) {
        status = DriveSyncStatus.pending;
        _notify();
      }
    });
  }

  static Future<DriveSyncModel> open(
    JournalBackup backup,
    PhotoStore photos, {
    Duration connectTimeout = const Duration(seconds: 30),
  }) async {
    final storage = DriveStorage.forPhotos(photos);
    try {
      final value = await storage.read();
      final device = value.deviceId;
      final account = value.account;
      final model = DriveSyncModel._(
        backup,
        photos,
        storage,
        device,
        account,
        value.enabled,
        connectTimeout,
      );
      if (account != null) {
        model._service = model._createService(account);
        try {
          await model._service!.load();
        } catch (error, stack) {
          reportError(error, stack);
          model.status = DriveSyncStatus.unavailable;
          model.lastError = DriveFailure.from(error, stack);
        }
      }
      await model._saveConfig();
      return model;
    } catch (error, stack) {
      reportError(error, stack);
      // Keep unreadable old files for recovery, but never make the diary read-only.
      return DriveSyncModel._(
          backup,
          photos,
          storage,
          storage.newDeviceId(),
          null,
          false,
          connectTimeout,
        )
        ..status = DriveSyncStatus.unavailable
        ..lastError = DriveFailure.from(error, stack);
    }
  }

  final JournalBackup backup;
  final PhotoStore photos;
  final DriveStorage storage;
  AtomicJsonFile get config => storage.config;
  final String deviceId;
  Duration connectTimeout;
  final client = const DriveNativeClient();
  late final NavigatorObserver observer;
  String? account;
  bool enabled;
  bool busy = false;
  bool foreground = true;
  bool _disposed = false;
  bool _applying = false;
  bool restoring = false;
  bool copiesLoaded = false;
  bool _dirty = true;
  int _revision = 0;
  Timer? _opening;
  StreamSubscription<void>? _changes;
  DriveBackups? _service;
  DriveSyncStatus status = DriveSyncStatus.pending;
  DriveFailure? lastError;
  List<DriveBackupCopy> copies = [];
  bool get applying => _applying;
  DateTime? get lastBackupAt => _service?.lastBackupAt;

  DriveBackups _createService(String account) => storage.backups(
    backup: backup,
    photos: photos,
    deviceId: deviceId,
    account: account,
    client: client,
  );

  Future<void> _saveConfig() => storage.save(
    DriveConfiguration(deviceId: deviceId, account: account, enabled: enabled),
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void lifecycle(AppLifecycleState state) {
    final wasForeground = foreground;
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _opening?.cancel();
      // Let the first frame and startup work finish before preparing a copy.
      _opening = Timer(const Duration(seconds: 2), () {
        if (_dirty && foreground) unawaited(synchronize());
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _opening?.cancel();
      if (_dirty) unawaited(synchronize());
    } else if (wasForeground) {
      _opening?.cancel();
    }
  }

  Future<void> _prepare({bool interactive = false}) async {
    final authorization = client.connect(interactive: interactive);
    final connected = interactive
        ? await authorization
        : await authorization.timeout(
            connectTimeout,
            onTimeout: () async {
              await client.cancel();
              throw TimeoutException('Drive authorization timed out');
            },
          );
    if (connected != account) throw StateError('Drive account changed');
    _service ??= _createService(connected);
  }

  Future<void> _operation(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    lastError = null;
    status = DriveSyncStatus.checking;
    _notify();
    try {
      await action();
    } catch (error, stack) {
      reportError(error, stack);
      status = DriveSyncStatus.unavailable;
      lastError = DriveFailure.from(error, stack);
      _dirty = true;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> enable() async {
    if (enabled) return;
    await _operation(() async {
      final connected = await client.connect(interactive: true);
      account = connected;
      _service = _createService(connected);
      enabled = true;
      await _saveConfig();
      await _saveCopy();
    });
  }

  Future<void> _saveCopy() async {
    final revision = _revision;
    await _service!.save();
    _dirty = revision != _revision;
    status = _dirty ? DriveSyncStatus.pending : DriveSyncStatus.current;
  }

  Future<void> synchronize({bool interactive = false}) async {
    if (!enabled) return;
    _opening?.cancel();
    await _operation(() async {
      await _prepare(interactive: interactive);
      await _saveCopy();
    });
  }

  Future<void> refreshCopies() async {
    if (!enabled) return;
    await _operation(() async {
      await _prepare(interactive: true);
      copies = await _service!.list();
      copiesLoaded = true;
      status = _dirty ? DriveSyncStatus.pending : DriveSyncStatus.current;
    });
  }

  Future<void> disable() async {
    await _operation(() async {
      // Disabling uploads is local and works even when Drive is offline.
      enabled = false;
      await _saveConfig();
      _opening?.cancel();
      try {
        await client.disconnect();
      } catch (error, stack) {
        reportError(error, stack);
      }
      copies = [];
      copiesLoaded = false;
      status = DriveSyncStatus.pending;
    });
  }

  Future<void> restore(DriveBackupCopy copy) async {
    if (!enabled) return;
    await _operation(() async {
      restoring = true;
      _notify();
      try {
        await _prepare(interactive: true);
        final payload = await _service!.read(copy);
        // Only explicit replacement closes the gate, after network work.
        await backup.database.transaction(() async {
          backup.database.writeGate.writable = false;
        });
        _applying = true;
        _notify();
        await _service!.safetyCopy();
        await _service!.restore(payload);
        _dirty = true;
        status = DriveSyncStatus.pending;
      } finally {
        backup.database.writeGate.writable = true;
        _applying = false;
        restoring = false;
        _notify();
      }
    });
  }

  Future<void> exportCopy(DriveBackupCopy copy) async {
    await _operation(() async {
      await _prepare(interactive: true);
      final payload = await _service!.read(copy);
      await storage.share(payload);
      status = _dirty ? DriveSyncStatus.pending : DriveSyncStatus.current;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _opening?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
