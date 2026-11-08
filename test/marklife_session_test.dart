import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/marklife_session.dart';
import 'package:holybeans/domain/marklife_protocol.dart';

Matcher fails(MarklifeFailure failure) => throwsA(
  isA<MarklifeException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  final pixels = Uint8List(320 * 96);
  for (final mtu in [23, 93, 247]) {
    test(
      'credit gate, packet cap and ACK during last write at MTU $mtu',
      () async {
        final chunks = <Uint8List>[];
        final expected = MarklifeProtocol.job(pixels, 40, MarklifePaper.gap);
        var count = 0;
        late MarklifeSession session;
        session = MarklifeSession(
          packetDelay: Duration.zero,
          write: (chunk) async {
            chunks.add(Uint8List.fromList(chunk));
            count += chunk.length;
            session.receiveControl(Uint8List.fromList([1, 1]));
            if (count == expected.length) {
              session.receive(Uint8List.fromList([0xaa]));
            }
          },
        )..setMtu(mtu);
        session.receiveControl(Uint8List.fromList([1, 1]));
        await session.print(pixels, 40, MarklifePaper.gap);
        expect(chunks.expand((c) => c), expected);
        expect(
          chunks.every((c) => c.length <= (mtu - 3).clamp(20, 90)),
          isTrue,
        );
        session.close();
      },
    );
  }
  test(
    'no credits means no writes; timeout cannot retry the session',
    () async {
      var writes = 0;
      final session = MarklifeSession(
        creditTimeout: const Duration(milliseconds: 20),
        write: (_) async {
          writes++;
        },
      );
      await expectLater(
        session.print(pixels, 40, MarklifePaper.gap),
        fails(MarklifeFailure.credits),
      );
      expect(writes, 0);
      session.receiveControl(Uint8List.fromList([1, 255]));
      await expectLater(
        session.print(pixels, 40, MarklifePaper.gap),
        fails(MarklifeFailure.disconnected),
      );
      expect(writes, 0);
    },
  );
  test('early and unknown ACKs do not confirm a later job', () async {
    var writes = 0;
    final session = MarklifeSession(
      packetDelay: Duration.zero,
      resultTimeout: const Duration(milliseconds: 20),
      write: (_) async {
        writes++;
      },
    )..setMtu(247);
    session.receive(Uint8List.fromList([0xaa]));
    session.receiveControl(Uint8List.fromList([1, 255]));
    await expectLater(
      session.print(pixels, 40, MarklifePaper.gap),
      fails(MarklifeFailure.unconfirmed),
    );
    expect(writes, greaterThan(0));
  });
  test('disconnect stops a job waiting for credits promptly', () async {
    var writes = 0;
    final session = MarklifeSession(
      write: (_) async {
        writes++;
      },
    );
    final result = expectLater(
      session.print(pixels, 40, MarklifePaper.gap),
      fails(MarklifeFailure.disconnected),
    );
    session.close();
    await result;
    expect(writes, 0);
  });
  test(
    'busy job cannot overlap and printer errors stop further packets',
    () async {
      var writes = 0;
      late MarklifeSession session;
      session = MarklifeSession(
        write: (_) async {
          writes++;
          session.receive(Uint8List.fromList([0xff, 2]));
        },
      );
      session.receiveControl(Uint8List.fromList([1, 4]));
      final first = expectLater(
        session.print(pixels, 40, MarklifePaper.gap),
        fails(MarklifeFailure.cover),
      );
      await expectLater(
        session.print(pixels, 40, MarklifePaper.gap),
        fails(MarklifeFailure.busy),
      );
      await first;
      expect(writes, 1);
    },
  );
  test('link failure during write never sends remaining data', () async {
    var writes = 0;
    final session = MarklifeSession(
      write: (_) async {
        writes++;
        throw StateError('lost');
      },
    );
    session.receiveControl(Uint8List.fromList([1, 4]));
    await expectLater(
      session.print(pixels, 40, MarklifePaper.gap),
      throwsStateError,
    );
    expect(writes, 1);
    await expectLater(
      session.print(pixels, 40, MarklifePaper.gap),
      fails(MarklifeFailure.disconnected),
    );
  });
  test(
    'device MTU only reduces negotiated payload; malformed control ignored',
    () {
      final session = MarklifeSession(write: (_) async {})..setMtu(247);
      session.receiveControl(Uint8List.fromList([2, 23, 0]));
      expect(session.payloadBytes, 20);
      session.receiveControl(Uint8List.fromList([2, 0]));
      session.receiveControl(Uint8List.fromList([2, 0, 0]));
      expect(session.payloadBytes, 20);
      session.close();
    },
  );
}
