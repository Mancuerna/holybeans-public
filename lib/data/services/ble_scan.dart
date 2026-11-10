import 'package:universal_ble/universal_ble.dart';

final sharedBleScan = BleScanCoordinator();

/// Keeps the native scan alive until its last user releases it.
class BleScanCoordinator {
  int _users = 0;
  Future<void>? _starting;
  Future<void> _stopping = Future.value();

  BleScanLease acquire() {
    _users++;
    final ready = _starting ??= _stopping.then((_) => UniversalBle.startScan());
    return BleScanLease._(ready, _release);
  }

  Future<void> _release() {
    if (--_users != 0) return Future.value();
    final starting = _starting!;
    _starting = null;
    // Owners receive startup failures through ready; cleanup must still run.
    final stopping = starting
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
        .then((_) => UniversalBle.stopScan());
    // Return stop failures to the releaser without blocking later scans.
    _stopping = stopping.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return stopping;
  }
}

class BleScanLease {
  BleScanLease._(this.ready, this._release);
  final Future<void> ready;
  final Future<void> Function() _release;
  Future<void>? _released;

  Future<void> release() => _released ??= _release();
}
