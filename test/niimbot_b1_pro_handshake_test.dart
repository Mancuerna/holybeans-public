import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';

void main() {
  for (final mode in ['fragmented', 'truncated', 'corrupt', 'silent']) {
    test('B1 Pro reports $mode status without bypassing validation', () async {
      final received = <Map<String, Object?>>[];
      late NiimbotSession session;
      session = NiimbotSession(
        model: LabelPrinterModel.b1Pro,
        responseTimeout: const Duration(milliseconds: 50),
        trace: (event, data) {
          if (event == 'niimbot.receive') received.add(data);
        },
        write: (bytes) async {
          final command = NiimbotDecoder().add(bytes).single.command;
          if (command == 0xc1) {
            session.receive(NiimbotPacket(0xc2, [3]).encode());
          } else if (command == 0x40) {
            session.receive(NiimbotPacket(0x48, [16, 1]).encode());
          } else if (command == 0xa5) {
            // 16-byte status payload, as in real reference captures: 23 on wire.
            final status = NiimbotPacket(0xb5, [
              ...List.filled(11, 0),
              3,
              2,
              0,
              0,
              0,
            ]).encode();
            if (mode == 'corrupt') {
              status[20] ^= 1;
              session.receive(status);
            } else if (mode != 'silent') {
              session.receive(Uint8List.sublistView(status, 0, 20));
              if (mode == 'fragmented') {
                session.receive(Uint8List.sublistView(status, 20));
              }
            }
          }
        },
      );
      if (mode == 'fragmented') {
        await session.identify();
        expect(session.identity?.protocolVersion, 5);
        expect(received[1]['buffered'], 20);
        expect(received[2]['bytes'], 3);
        expect(received[2]['decoded'], 1);
        final count = received.length;
        session.receive(NiimbotPacket(0xb5, [1]).encode());
        expect(received, hasLength(count)); // No capture after identification.
      } else {
        await expectLater(
          session.identify(),
          throwsA(
            isA<LabelPrintException>().having(
              (e) => e.failure,
              'failure',
              LabelPrintFailure.timeout,
            ),
          ),
        );
        expect(session.identity, isNull);
        final statusEvents = received.where((e) => e['expected'] == 0xb5);
        if (mode == 'silent') {
          expect(statusEvents, isEmpty);
        } else {
          final event = statusEvents.single;
          expect(event['decoded'], 0);
          expect(event['invalidFrames'], mode == 'corrupt' ? 1 : 0);
          if (mode == 'truncated') expect(event['buffered'], 20);
        }
        await expectLater(
          session.print(Uint8List(576), 576),
          throwsA(isA<LabelPrintException>()),
        );
      }
    });
  }
  for (final actualModel in [4097, 4096]) {
    test(
      'B1 Pro negotiates status before validating model $actualModel',
      () async {
        final sent = <int>[];
        late NiimbotSession session;
        session = NiimbotSession(
          model: LabelPrinterModel.b1Pro,
          responseTimeout: const Duration(milliseconds: 100),
          write: (bytes) async {
            final packet = NiimbotDecoder().add(bytes).single;
            sent.add(packet.command);
            final response = switch (sent.length) {
              1 => NiimbotPacket(0xc2, [3]), // Observed on the user's unit.
              2 => NiimbotPacket(0xb5, [...List.filled(11, 0), 3, 2]),
              3 => NiimbotPacket(0x48, niimbotU16(actualModel)),
              _ => throw StateError('Unexpected extra request'),
            };
            expect(packet.command, [0xc1, 0xa5, 0x40][sent.length - 1]);
            session.receive(response.encode());
          },
        );
        if (actualModel == 4097) {
          await session.identify();
          expect(session.identity?.id, 4097);
          expect(session.identity?.protocolVersion, 5);
        } else {
          await expectLater(
            session.identify(),
            throwsA(isA<LabelPrintException>()),
          );
          expect(session.identity, isNull);
        }
        expect(sent, [0xc1, 0xa5, 0x40]);
      },
    );
  }

  test(
    'unexpected status reply is logged but cannot bypass negotiation',
    () async {
      final sent = <int>[];
      final events = <(String, Map<String, Object?>)>[];
      late NiimbotSession session;
      session = NiimbotSession(
        model: LabelPrinterModel.b1Pro,
        responseTimeout: const Duration(milliseconds: 30),
        trace: (event, data) => events.add((event, data)),
        write: (bytes) async {
          final command = NiimbotDecoder().add(bytes).single.command;
          sent.add(command);
          session.receive(
            NiimbotPacket(command == 0xc1 ? 0xc2 : 0xb4, [3]).encode(),
          );
        },
      );
      await expectLater(
        session.identify(),
        throwsA(
          isA<LabelPrintException>().having(
            (e) => e.failure,
            'failure',
            LabelPrintFailure.timeout,
          ),
        ),
      );
      expect(
        events.where((e) => e.$1 == 'niimbot.unexpectedResponse').single.$2,
        {'command': 0xb4, 'expected': 0xb5, 'length': 1},
      );
      expect(session.identity, isNull);
      await expectLater(
        session.print(Uint8List(576), 576),
        throwsA(isA<LabelPrintException>()),
      );
      expect(sent, [0xc1, 0xa5]);
    },
  );
}
