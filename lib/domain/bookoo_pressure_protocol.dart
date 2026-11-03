/// The BOOKOO Espresso Monitor Bluetooth protocol.
///
/// Source: https://github.com/BooKooCode/OpenSource/blob/main/espresso_monitor/protocols.md.
/// HolyBeans only starts and stops pressure transmission.
library;

/// The service and extraction data characteristic of the pressure sensor.
abstract final class BookooPressureUuids {
  static const service = '00000fff-0000-1000-8000-00805f9b34fb';
  static const pressure = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const command = '0000ff01-0000-1000-8000-00805f9b34fb';
}

/// The manufacturer's command that starts pressure transmission.
const bookooStartPressure = <int>[0x02, 0x0c, 0x01, 0x00, 0x00, 0x00, 0x0f];

/// The manufacturer's command that stops pressure transmission.
const bookooStopPressure = <int>[0x02, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x0e];

/// Whether [name] identifies a BOOKOO Espresso Monitor.
bool isBookooPressureName(String? name) =>
    name != null && name.toUpperCase().startsWith('BOOKOO_EM');

/// Reads the pressure in bar from an extraction data notification.
///
/// The documented frame has ten bytes, starts with `02 1B` and stores
/// unsigned pressure × 100 in bytes 4–5, most significant byte first.
/// Unlike command frames, extraction frames have no documented checksum.
/// Returns `null` for incomplete frames, other messages or invalid bytes.
double? parseBookooPressureBar(List<int> packet) {
  if (packet.length != 10 ||
      packet[0] != 0x02 ||
      packet[1] != 0x1b ||
      packet.any((byte) => byte < 0 || byte > 0xff)) {
    return null;
  }
  return ((packet[4] << 8) | packet[5]) / 100;
}
