import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/timemore_dot_protocol.dart';

import 'helpers/fake_dot_ble_platform.dart';

void main() {
  test('reserved zero CRC never accepts nonzero corrupt trailers', () {
    final packet = [0xa5, 0x5a, 2, 6, 0, 1, 0, 0, 0];
    expect(DotDecoder().add(packet), isEmpty);
    final decoder = DotDecoder(allowReservedZeroCrc: true);
    expect(decoder.add(packet.take(7).toList()), isEmpty);
    final frames = decoder.add([
      ...packet.skip(7),
      ...packet.take(8),
      1,
      ...packet,
    ]);
    expect(frames, hasLength(2));
    expect(frames.every((f) => !f.crcVerified), isTrue);
  });

  test('CRC known vector and independently captured documented tare', () {
    expect(dotCrc(ascii.encode('123456789')), 0x4b37);
    expect(dotCommands(ScaleCommand.tare).single, [
      0xa5,
      0x5a,
      3,
      13,
      0,
      0,
      0x64,
      0xd1,
    ]);
  });

  test(
    'fragmented and coalesced frames survive noise and invalid length/CRC',
    () {
      final rejected = <String>[];
      final decoder = DotDecoder(
        onRejected: (reason, _) => rejected.add(reason),
      );
      final weight = dotWeight(-123, flow: -20, seconds: 42);
      expect(decoder.add([7, 0xa5, 7, ...weight.take(4)]), isEmpty);
      final badCrc = [...weight]..[8] ^= 1;
      final frames = decoder.add([
        ...weight.skip(4),
        ...badCrc,
        0xa5,
        0x5a,
        1,
        1,
        255,
        255,
        ...weight,
        ...dotReply(2, 5, [2, 76]),
      ]);
      expect(frames.map((f) => f.command), [1, 1, 5]);
      expect(rejected, containsAll(['crc', 'length']));
    },
  );

  test(
    'reads signed tenths, seconds, timer state and battery only in known grams',
    () {
      final state = DotState();
      final decoder = DotDecoder();
      final weight = decoder
          .add(dotWeight(-123, flow: -20, seconds: 42))
          .single;
      expect(state.accept(weight), isNull);
      for (final bytes in [
        dotReply(2, 6, [0]),
        dotReply(2, 5, [2, 76]),
        dotReply(1, 2, [1]),
      ]) {
        expect(state.accept(decoder.add(bytes).single), isNull);
      }
      final reading = state.accept(weight)!;
      expect(reading.grams, -12.3);
      expect(reading.flowGramsPerSecond, -2);
      expect(reading.timerMs, 42000);
      expect(reading.timerRunning, isTrue);
      expect(reading.batteryPercent, 76);
      state.accept(decoder.add(dotReply(1, 2, [2])).single);
      expect(state.accept(weight)!.timerRunning, isFalse);
      // A command ACK is not a timer-state notification.
      state.accept(decoder.add(dotReply(3, 2, [1])).single);
      expect(state.accept(weight)!.timerRunning, isFalse);
      for (final unit in [1, 9]) {
        state.accept(decoder.add(dotReply(1, 6, [unit])).single);
        expect(state.accept(weight), isNull);
      }
    },
  );

  test('overload, short packets and invalid time never become weight', () {
    final state = DotState()..unit = 0;
    final decoder = DotDecoder();
    for (final bytes in [
      dotWeight(12000, overload: 1),
      dotWeight(10, seconds: 3600),
      dotReply(1, 1, [0]),
      dotReply(2, 1, List.filled(9, 0)),
    ]) {
      expect(state.accept(decoder.add(bytes).single), isNull);
    }
  });

  test('commands expose only explicit tare and timer actions', () {
    final decoder = DotDecoder();
    expect(
      dotCommands(ScaleCommand.tareAndStartTimer)
          .expand(decoder.add)
          .map((f) => [f.operation, f.command, f.payload.toList()]),
      [
        [3, 13, <int>[]],
        [
          3,
          2,
          [3],
        ],
        [
          3,
          2,
          [1],
        ],
      ],
    );
    expect(
      DotQuery.values
          .map(dotQuery)
          .expand(decoder.add)
          .map((f) => (f.operation, f.command, f.payload.length)),
      [(2, 2, 0), (2, 5, 0), (2, 6, 0)],
    );
  });
}
