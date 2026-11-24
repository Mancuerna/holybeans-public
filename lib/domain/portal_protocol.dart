import 'dart:typed_data';

abstract final class PortalProtocol {
  static const service = '00007400-0000-1000-8000-00805f9b34fb';
  static const measurement = '00007410-0000-1000-8000-00805f9b34fb';
  static const command = '00007420-0000-1000-8000-00805f9b34fb';
  static const showGraph = [0x40, 0x00, 0x01, 0x2d];
  static const hideGraph = [0x40, 0x00, 0x01, 0x2e];

  static PortalReading? parse(Uint8List packet) {
    if (packet.length != 13) return null;
    final data = ByteData.sublistView(packet);
    final ec = data.getFloat32(0, Endian.little);
    final internal = data.getFloat32(4, Endian.little);
    final outlet = data.getFloat32(8, Endian.little);
    if (!ec.isFinite || !internal.isFinite || !outlet.isFinite) return null;
    return (ec: ec, internal: internal, outlet: outlet, status: packet[12]);
  }
}

typedef PortalReading = ({
  double ec,
  double internal,
  double outlet,
  int status,
});
typedef PortalSample = ({int ms, PortalReading reading, bool start});

/// Raw samples on the brew timer. The display offset never changes sample time.
class PortalRecording {
  PortalRecording(this.samples, {this.offsetMs = 0});
  factory PortalRecording.fromJson(Object? json) {
    if (json case {
      'offset': final int offset,
      'samples': final List<Object?> rows,
    }) {
      final samples = <PortalSample>[];
      for (final row in rows) {
        if (row
            case [
              final int ms,
              final num ec,
              final num internal,
              final num outlet,
              final int status,
              final bool start,
            ]
            when ms >= 0 &&
                ec.isFinite &&
                internal.isFinite &&
                outlet.isFinite &&
                status >= 0 &&
                status <= 255) {
          samples.add((
            ms: ms,
            start: start,
            reading: (
              ec: ec.toDouble(),
              internal: internal.toDouble(),
              outlet: outlet.toDouble(),
              status: status,
            ),
          ));
        } else {
          throw const FormatException('Invalid Portal sample');
        }
      }
      return PortalRecording(samples, offsetMs: offset);
    }
    throw const FormatException('Invalid Portal recording');
  }

  final List<PortalSample> samples;
  final int offsetMs;

  Map<String, Object> toJson() => {
    'offset': offsetMs,
    'samples': [
      for (final s in samples)
        [
          s.ms,
          s.reading.ec,
          s.reading.internal,
          s.reading.outlet,
          s.reading.status,
          s.start,
        ],
    ],
  };
}
