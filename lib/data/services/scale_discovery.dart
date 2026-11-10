import 'dart:async';

import 'package:holybeans/data/services/ble_scan.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:universal_ble/universal_ble.dart';

/// A bounded scan of already paired identities, in most recently used order.
class ScaleDiscovery {
  ScaleDiscovery({this.duration = const Duration(seconds: 3)});

  final Duration duration;
  Completer<void>? _done;

  void cancel() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<List<FoundDevice>> nearby(List<FoundDevice> remembered) async {
    final seen = <String>{};
    final done = Completer<void>();
    _done = done;
    final subscription = UniversalBle.scanStream.listen((device) {
      seen.add(device.deviceId);
      // Finish early only once all known candidates have advertised.
      if (remembered.every((d) => seen.contains(d.id)) && !done.isCompleted) {
        done.complete();
      }
    });
    final lease = sharedBleScan.acquire();
    Timer? timer;
    try {
      await lease.ready;
      timer = Timer(duration, () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      return remembered.where((device) => seen.contains(device.id)).toList();
    } finally {
      timer?.cancel();
      await subscription.cancel();
      if (identical(_done, done)) _done = null;
      await lease.release();
    }
  }
}
