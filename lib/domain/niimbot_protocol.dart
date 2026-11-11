import 'dart:typed_data';

import 'package:holybeans/domain/label_printer_profile.dart';

// Protocol reference: MultiMote/niimbluelib (MIT), see bundled license.
class NiimbotPacket {
  NiimbotPacket(this.command, List<int> payload)
    : payload = List.unmodifiable(payload);

  final int command;
  final List<int> payload;

  Uint8List encode() {
    if (payload.length > 255 ||
        command < 0 ||
        command > 255 ||
        payload.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid Niimbot packet');
    }
    final checksum = payload.fold(command ^ payload.length, (a, b) => a ^ b);
    return Uint8List.fromList([
      if (command == 0xc1) 3,
      0x55,
      0x55,
      command,
      payload.length,
      ...payload,
      checksum,
      0xaa,
      0xaa,
    ]);
  }
}

class NiimbotDecoder {
  final _buffer = <int>[];
  int get bufferedBytes => _buffer.length;
  int get invalidFrames => _invalidFrames;
  int _invalidFrames = 0;

  List<NiimbotPacket> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final result = <NiimbotPacket>[];
    while (_buffer.length >= 7) {
      if (_buffer[0] != 0x55 || _buffer[1] != 0x55) {
        _buffer.removeAt(0);
        continue;
      }
      final length = _buffer[3];
      final end = length + 7;
      if (_buffer.length < end) break;
      final payload = _buffer.sublist(4, length + 4);
      final checksum = payload.fold(_buffer[2] ^ length, (a, b) => a ^ b);
      if (_buffer[end - 2] != 0xaa ||
          _buffer[end - 1] != 0xaa ||
          _buffer[end - 3] != checksum) {
        _invalidFrames++;
        _buffer.removeAt(0);
        continue;
      }
      result.add(NiimbotPacket(_buffer[2], payload));
      _buffer.removeRange(0, end);
    }
    return result;
  }
}

List<int> niimbotU16(int value) => [(value >> 8) & 255, value & 255];

// Pixels are in landscape order, one byte per pixel: 1 black, 0 white.
// D110 feeds the landscape label rotated 90 degrees clockwise.
List<NiimbotPacket> niimbotImageRows(
  Uint8List pixels,
  int width, {
  LabelPrinterModel model = LabelPrinterModel.d110,
  bool totalCounts = false,
  bool checkLines = false,
}) {
  final height = width > 0 ? pixels.length ~/ width : 0;
  if (width < 1 ||
      width > 1600 ||
      height < 1 ||
      height > 1600 ||
      pixels.length != width * height ||
      (model.rotateForFeed
          ? (model == LabelPrinterModel.d11H
                ? height > model.headPixels
                : height != model.headPixels)
          : width > model.headPixels) ||
      pixels.any((pixel) => pixel > 1)) {
    throw const FormatException('Invalid Niimbot bitmap');
  }
  final rowCount = model.rotateForFeed ? width : height;
  final columns = (model.rotateForFeed ? height + 7 : width + 7) ~/ 8 * 8;
  final packets = <NiimbotPacket>[];
  for (var row = 0; row < rowCount; row++) {
    final data = List<int>.filled(columns ~/ 8, 0);
    final counts = List<int>.filled(3, 0);
    for (var col = 0; col < columns; col++) {
      if (col >= (model.rotateForFeed ? height : width)) continue;
      final index = model.rotateForFeed
          ? (height - 1 - col) * width + row
          : row * width + col;
      if (pixels[index] == 0) continue;
      data[col ~/ 8] |= 1 << (7 - col % 8);
      counts[col ~/ (model.headPixels ~/ 3)]++;
    }
    final total = counts.fold(0, (a, b) => a + b);
    final headerCounts = totalCounts ? [0, total & 255, total >> 8] : counts;
    packets.add(
      counts.every((n) => n == 0)
          ? NiimbotPacket(0x84, [...niimbotU16(row), 1])
          : NiimbotPacket(0x85, [
              ...niimbotU16(row),
              ...headerCounts,
              1,
              ...data,
            ]),
    );
    if (checkLines && row % 200 == 199) {
      packets.add(NiimbotPacket(0x86, [...niimbotU16(row), 1]));
    }
  }
  return packets;
}
