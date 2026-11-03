import 'package:holybeans/domain/bookoo_protocol.dart';

List<int> bookooDosePacket(int centigrams, {int sign = 0x2B}) {
  final packet = <int>[
    0x03,
    0x0F,
    sign,
    (centigrams >> 16) & 0xFF,
    (centigrams >> 8) & 0xFF,
    centigrams & 0xFF,
    ...List<int>.filled(13, 0),
  ];
  return [...packet, bookooChecksum(packet)];
}
