import 'package:universal_ble/universal_ble.dart';

typedef BleTrace = void Function(String event, Map<String, Object?> data);

String bleHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

Map<String, Object?> bleServices(List<BleService> services) => {
  'services': [
    for (final service in services)
      {
        'uuid': service.uuid,
        'characteristics': [
          for (final c in service.characteristics) c.toJson(),
        ],
      },
  ],
};

/// A diagnostic observer must never change the Bluetooth operation's outcome.
void emitBleTrace(BleTrace? trace, String event, Map<String, Object?> data) {
  if (trace == null) return;
  try {
    trace(event, data);
  } on Object {
    // Diagnostics are optional; the normal connection remains usable.
  }
}
