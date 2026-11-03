import 'dart:async';

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
    Timer? timer;
    try {
      await UniversalBle.startScan();
      timer = Timer(duration, cancel);
      await done.future;
      return remembered.where((device) => seen.contains(device.id)).toList();
    } finally {
      timer?.cancel();
      await subscription.cancel();
      _done = null;
      await UniversalBle.stopScan();
    }
  }
}
