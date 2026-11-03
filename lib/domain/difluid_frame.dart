/// Frames shared by the documented DiFluid cleartext protocols.
library;

/// Builds a frame with a checksum equal to the byte sum modulo 256.
List<int> difluidFrame(int function, int command, [List<int> data = const []]) {
  final frame = [0xdf, 0xdf, function, command, data.length, ...data];
  return [...frame, frame.fold(0, (sum, byte) => sum + byte) & 0xff];
}

/// Validates a complete notification before exposing its payload.
({int function, int command, List<int> data})? parseDifluidFrame(
  List<int> packet,
) {
  if (packet.length < 6 ||
      packet[0] != 0xdf ||
      packet[1] != 0xdf ||
      packet[4] != packet.length - 6 ||
      packet.any((byte) => byte < 0 || byte > 255)) {
    return null;
  }
  final sum = packet.take(packet.length - 1).fold(0, (sum, byte) => sum + byte);
  if ((sum & 0xff) != packet.last) return null;
  return (
    function: packet[2],
    command: packet[3],
    data: packet.sublist(5, packet.length - 1),
  );
}
