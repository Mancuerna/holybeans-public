import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/bookoo_protocol.dart';

/// A weight packet as the scale sends it, with its checksum.
List<int> packet({
  int timerMs = 0,
  int centigrams = 0,
  bool negative = false,
  int flow = 0,
  int battery = 80,
}) {
  final body = [
    0x03,
    0x0B,
    (timerMs >> 16) & 0xFF,
    (timerMs >> 8) & 0xFF,
    timerMs & 0xFF,
    0x01,
    negative ? 0x2D : 0x2B,
    (centigrams >> 16) & 0xFF,
    (centigrams >> 8) & 0xFF,
    centigrams & 0xFF,
    0x2B,
    (flow >> 8) & 0xFF,
    flow & 0xFF,
    battery,
    0x00,
    0x32,
    0x01,
    0x00,
    0x00,
  ];
  return [...body, bookooChecksum(body)];
}

void main() {
  test('commands match the ones the maker documents', () {
    List<int> bytes(ScaleCommand command) => bookooCommandBytes(command);
    // Tare, timer and tare-and-start, as listed in the protocol.
    expect(bytes(ScaleCommand.tare), [0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]);
    expect(bytes(ScaleCommand.startTimer), [3, 0x0A, 0x04, 0, 0, 0x0D]);
    expect(bytes(ScaleCommand.stopTimer), [3, 0x0A, 0x05, 0, 0, 0x0C]);
    expect(bytes(ScaleCommand.resetTimer), [3, 0x0A, 0x06, 0, 0, 0x0F]);
    expect(bytes(ScaleCommand.tareAndStartTimer), [3, 0x0A, 7, 0, 0, 0x0E]);
  });

  test('a weight packet gives weight, flow, timer and battery', () {
    final reading = parseBookooWeight(
      packet(timerMs: 95300, centigrams: 25012, flow: 375, battery: 64),
    )!;
    expect(reading.grams, 250.12);
    expect(reading.flowGramsPerSecond, 3.75);
    expect(reading.timerMs, 95300);
    expect(reading.batteryPercent, 64);

    // Lifting the jug after taring reads below zero.
    expect(
      parseBookooWeight(packet(centigrams: 320, negative: true))!.grams,
      -3.2,
    );
    // Weights above 655 g need the third byte.
    expect(parseBookooWeight(packet(centigrams: 120000))!.grams, 1200);
  });

  test('other packets and corrupted ones are ignored', () {
    final good = packet(centigrams: 1500);
    expect(parseBookooWeight(good.sublist(0, 19)), isNull);
    expect(parseBookooWeight([...good.sublist(0, 19), good[19] ^ 1]), isNull);
    // Powder weight (type 0F) is another packet.
    final powder = [...good]..[1] = 0x0F;
    powder[19] = bookooChecksum(powder.take(19));
    expect(parseBookooWeight(powder), isNull);
  });

  test('scales are told apart by their advertised name', () {
    expect(isBookooScaleName('BOOKOO_SC_U'), isTrue);
    expect(isBookooScaleName('BOOKOO_SC'), isTrue);
    expect(isBookooScaleName('bookoo_sc'), isTrue);
    expect(isBookooScaleName('BOOKOO_EM'), isFalse);
    expect(isBookooScaleName(null), isFalse);
  });
}
