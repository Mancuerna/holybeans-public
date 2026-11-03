/// The Bluetooth protocol of BOOKOO scales (Themis Mini and Ultra), as
/// published by the maker:
/// https://github.com/BooKooCode/OpenSource (MIT). Weight packets arrive by
/// notification on characteristic FF11 and commands are written to FF12,
/// both in service 0FFE.
library;

import 'package:holybeans/domain/scale_recording.dart';

export 'package:holybeans/domain/scale_recording.dart'
    show ScaleCommand, ScaleReading;

/// Full 128-bit UUIDs of the scale's service and characteristics.
abstract final class BookooUuids {
  static const service = '00000ffe-0000-1000-8000-00805f9b34fb';
  static const weight = '0000ff11-0000-1000-8000-00805f9b34fb';
  static const command = '0000ff12-0000-1000-8000-00805f9b34fb';
}

/// Whether a device advertising [name] is a BOOKOO scale: the Mini shows
/// up as "BOOKOO_SC" and the Ultra as "BOOKOO_SC_U".
bool isBookooScaleName(String? name) =>
    name != null && name.toUpperCase().startsWith('BOOKOO_SC');

/// XOR of [bytes], the checksum both directions end with.
int bookooChecksum(Iterable<int> bytes) =>
    bytes.fold(0, (sum, byte) => sum ^ byte);

/// Reads a weight packet (product 03, type 0B, 20 bytes), or returns null
/// for anything else: another packet type, a short one or a bad checksum.
ScaleReading? parseBookooWeight(List<int> packet) {
  if (packet.length != 20 || packet[0] != 0x03 || packet[1] != 0x0B) {
    return null;
  }
  if (bookooChecksum(packet.take(19)) != packet[19]) return null;
  int unsigned(int from, int length) {
    var value = 0;
    for (var i = from; i < from + length; i++) {
      value = (value << 8) | packet[i];
    }
    return value;
  }

  // Signs come as ASCII '+' or '-'.
  double signed(int signAt, int value) =>
      (packet[signAt] == 0x2D ? -value : value) / 100;
  return ScaleReading(
    timerMs: unsigned(2, 3),
    grams: signed(6, unsigned(7, 3)),
    flowGramsPerSecond: signed(10, unsigned(11, 2)),
    batteryPercent: packet[13],
  );
}

/// The six bytes that ask the scale for [command], checksum included. The
/// maker documents more commands (calibration, beeps, auto-off, shutdown)
/// that the app leaves alone.
List<int> bookooCommandBytes(ScaleCommand command) {
  final code = switch (command) {
    ScaleCommand.tare => 0x01,
    ScaleCommand.startTimer => 0x04,
    ScaleCommand.stopTimer => 0x05,
    ScaleCommand.resetTimer => 0x06,
    // The maker's recommended way to begin a brew.
    ScaleCommand.tareAndStartTimer => 0x07,
  };
  final body = [0x03, 0x0A, code, 0x00, 0x00];
  return [...body, bookooChecksum(body)];
}
