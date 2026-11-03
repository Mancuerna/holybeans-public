import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';

class PrinterHarness {
  PrinterHarness({LabelPrinterModel profile = LabelPrinterModel.d110}) {
    model = switch (profile) {
      LabelPrinterModel.d110 => 2304,
      LabelPrinterModel.d11 => 512,
      LabelPrinterModel.d11H => 528,
      LabelPrinterModel.b1 => 4096,
      LabelPrinterModel.b1Pro => 4097,
      LabelPrinterModel.b21 => 768,
      LabelPrinterModel.b2 => 6913,
      LabelPrinterModel.b2Pro => 6912,
    };
    session = NiimbotSession(
      write: send,
      model: profile,
      responseTimeout: const Duration(milliseconds: 40),
      printTimeout: const Duration(milliseconds: 100),
      pollInterval: const Duration(milliseconds: 1),
    );
  }
  late final NiimbotSession session;
  final commands = <NiimbotPacket>[];
  int model = 2304;
  int hello = 1;
  List<int>? legacyPage;
  int revision = 302;
  final busyReplies = <int, int>{};
  bool shortModel = false;
  int? silent;
  int? reject;
  int? lose;
  int copies = 1;
  bool neverFinish = false;
  Completer<void>? holdRows;

  Future<void> send(Uint8List bytes) async {
    final p = NiimbotDecoder().add(bytes).single;
    commands.add(p);
    if (p.command == silent) return;
    if (p.command == lose) {
      session.close();
      return;
    }
    if (p.command == reject) {
      session.receive(NiimbotPacket(0xdb, [2]).encode());
      return;
    }
    if (p.command == 0x15 ||
        (p.command == 0x01 &&
            (p.payload.length == 7 || p.payload.length == 9))) {
      copies = p.payload[0] * 256 + p.payload[1];
    }
    if (p.command == 0x84 || p.command == 0x85) {
      await holdRows?.future;
      return;
    }
    if ((busyReplies[p.command] ?? 0) > 0) {
      busyReplies[p.command] = busyReplies[p.command]! - 1;
      session.receive(
        NiimbotPacket({0x03: 0x04, 0xe3: 0xe4, 0xf3: 0xf4}[p.command]!, [
          0,
        ]).encode(),
      );
      return;
    }
    final response = switch (p.command) {
      0xa5 => NiimbotPacket(0xb5, [
        ...List.filled(11, 0),
        revision ~/ 100,
        revision % 100,
      ]),
      0x86 => NiimbotPacket(0xd3, p.payload.take(2).toList()),
      0xc1 => NiimbotPacket(0xc2, [hello]),
      0x40 => NiimbotPacket(
        0x48,
        shortModel ? [model >> 8] : niimbotU16(model),
      ),
      0x21 => NiimbotPacket(0x31, [2]),
      0x23 => NiimbotPacket(0x33, [1]),
      0x01 => NiimbotPacket(0x02, [1]),
      0x20 => NiimbotPacket(0x30, [1]),
      0x03 => NiimbotPacket(0x04, [1]),
      0x13 => NiimbotPacket(0x14, [1]),
      0x15 => NiimbotPacket(0x16, [1]),
      0xe3 => NiimbotPacket(0xe4, [1]),
      0xa3 => NiimbotPacket(0xb3, [0, neverFinish ? 0 : copies, 100, 100]),
      0xf3 => NiimbotPacket(0xf4, [1]),
      _ => throw StateError('Unexpected command: ${p.command}'),
    };
    if (p.command == 0xe3 && legacyPage != null) {
      session.receive(NiimbotPacket(0xe0, legacyPage!).encode());
    }
    final frame = response.encode();
    session.receive(Uint8List.sublistView(frame, 0, 3));
    session.receive(Uint8List.sublistView(frame, 3));
  }
}

void main() {
  for (final profile in [
    LabelPrinterModel.b1Pro,
    LabelPrinterModel.b2Pro,
    LabelPrinterModel.b2,
  ]) {
    final handshake = profile == LabelPrinterModel.b1Pro
        ? [0xc1, 0xa5, 0x40]
        : [0xc1, 0x40, 0xa5];
    test(
      '${profile.label} negotiates V4 and pads page width without rotating',
      () async {
        final h = PrinterHarness(profile: profile);
        await h.session.identify();
        expect(h.commands.map((p) => p.command), handshake);
        await h.session.print(Uint8List(354 * 2)..[353] = 1, 354, copies: 3);
        expect(h.commands.take(8).map((p) => p.command), [
          ...handshake,
          0x23,
          0x21,
          0x01,
          0xa3,
          0x13,
        ]);
        expect(h.commands.firstWhere((p) => p.command == 0x01).payload, [
          0,
          3,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
        expect(h.commands.firstWhere((p) => p.command == 0x13).payload, [
          0,
          2,
          1,
          104,
          0,
          3,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(
          h.commands.where(
            (p) => p.command == 0x03 || p.command == 0x20 || p.command == 0x15,
          ),
          isEmpty,
        );
        expect(
          h.commands.where((p) => p.command == 0x85).single.payload.last,
          64,
        );
        expect(h.commands.last.command, 0xf3);
      },
    );
    test(
      '${profile.label} cannot print with an unrecognized protocol',
      () async {
        for (final revision in [0, 204, 400]) {
          final h = PrinterHarness(profile: profile)..revision = revision;
          await expectLater(
            h.session.identify(),
            throwsA(isA<LabelPrintException>()),
          );
          await expectLater(
            h.session.print(Uint8List(384), 384),
            throwsA(isA<LabelPrintException>()),
          );
          expect(h.commands.map((p) => p.command), handshake);
        }
      },
    );
  }
  for (final id in [768, 769]) {
    test(
      'B21 $id sends each requested copy and checks row checkpoints',
      () async {
        final h = PrinterHarness(profile: LabelPrinterModel.b21)..model = id;
        if (id == 768) h.busyReplies[0xf3] = 1;
        if (id == 769) {
          h.busyReplies[0x03] = 1;
          h.busyReplies[0xe3] = 1;
        }
        await h.session.identify();
        await h.session.print(
          Uint8List(384 * 201)..fillRange(0, 384, 1),
          384,
          copies: 2,
        );
        expect(h.commands.where((p) => p.command == 0x13), hasLength(2));
        expect(h.commands.firstWhere((p) => p.command == 0x13).payload, [
          0,
          201,
          1,
          128,
        ]);
        expect(h.commands.where((p) => p.command == 0x85), hasLength(2));
        expect(
          h.commands.firstWhere((p) => p.command == 0x85).payload.take(6),
          [0, 0, 0, 128, 1, 1],
        );
        expect(
          h.commands.where((p) => p.command == 0x86).map((p) => p.payload),
          [
            [0, 199, 1],
            [0, 199, 1],
          ],
        );
        expect(
          h.commands.where((p) => p.command == 0xa3 || p.command == 0x15),
          isEmpty,
        );
        expect(
          h.commands.where((p) => p.command == 0xf3),
          hasLength(id == 768 ? 2 : 1),
        );
        if (id == 769) {
          expect(h.commands.where((p) => p.command == 0xe3), hasLength(4));
        }
      },
    );
  }
  test('B21 L2B readiness timeout cannot send or retry a page', () async {
    final h = PrinterHarness(profile: LabelPrinterModel.b21)..model = 769;
    h.busyReplies[0x03] = 10000;
    await h.session.identify();
    await expectLater(
      h.session.print(Uint8List(384), 384),
      throwsA(isA<LabelPrintException>()),
    );
    expect(
      h.commands.where((p) => p.command == 0x13 || p.command == 0x84),
      isEmpty,
    );
    expect(h.commands.where((p) => p.command == 0x01), hasLength(1));
  });
  for (final id in [771, 775, 776, 777]) {
    test(
      'B21 $id selects its family while preserving top-feed geometry',
      () async {
        final h = PrinterHarness(profile: LabelPrinterModel.b21)..model = id;
        await h.session.identify();
        await h.session.print(Uint8List(384 * 2), 384);
        expect(
          h.commands.firstWhere((p) => p.command == 0x13).payload.take(4),
          [0, 2, 1, 128],
        );
        expect(h.commands.where((p) => p.command == 0x84), hasLength(2));
        expect(
          h.commands.any((p) => p.command == 0x20),
          id == 776 || id == 777,
        );
      },
    );
  }

  test(
    'B1 uses its own job framing, top feed, size and copy quantity',
    () async {
      final h = PrinterHarness(profile: LabelPrinterModel.b1)
        ..shortModel = true;
      await h.session.identify();
      await h.session.print(Uint8List(384 * 240), 384, copies: 3);
      expect(h.commands.take(7).map((p) => p.command), [
        0xc1,
        0x40,
        0x21,
        0x23,
        0x01,
        0x03,
        0x13,
      ]);
      expect(h.commands.firstWhere((p) => p.command == 0x01).payload, [
        0,
        3,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(h.commands.firstWhere((p) => p.command == 0x13).payload, [
        0,
        240,
        1,
        128,
        0,
        3,
      ]);
      expect(h.commands.firstWhere((p) => p.command == 0x21).payload, [3]);
      expect(h.commands.where((p) => p.command == 0x84), hasLength(240));
      expect(
        h.commands.where((p) => p.command == 0x15 || p.command == 0x20),
        isEmpty,
      );
      expect(h.commands.last.command, 0xf3);
    },
  );

  test('B1 rejects D110, Pro and SE identities before job setup', () async {
    for (final id in [2304, 4097, 4098]) {
      final h = PrinterHarness(profile: LabelPrinterModel.b1)..model = id;
      await expectLater(
        h.session.identify(),
        throwsA(isA<LabelPrintException>()),
      );
      await expectLater(
        h.session.print(Uint8List(384), 384),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands.map((p) => p.command), [0xc1, 0x40]);
    }
  });

  test(
    'identifies without printing, prints exact copies and waits for status',
    () async {
      final h = PrinterHarness();
      await h.session.identify();
      expect(h.commands.map((p) => p.command), [0xc1, 0x40]);
      await h.session.print(Uint8List(240 * 96), 240, copies: 2);
      final commands = h.commands.map((p) => p.command).toList();
      expect(commands.take(9), [
        0xc1,
        0x40,
        0x21,
        0x23,
        0x01,
        0x20,
        0x03,
        0x13,
        0x15,
      ]);
      expect(commands.where((p) => p == 0x84), hasLength(240));
      expect(commands.skip(commands.length - 3), [0xe3, 0xa3, 0xf3]);
      expect(h.commands.firstWhere((p) => p.command == 0x15).payload, [0, 2]);
    },
  );

  test(
    'model name cannot bypass identification; D110_M gets no print commands',
    () async {
      final h = PrinterHarness()..model = 2320;
      await expectLater(
        h.session.identify(),
        throwsA(isA<LabelPrintException>()),
      );
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands.map((p) => p.command), [0xc1, 0x40]);
    },
  );

  test('accepts the documented one-byte D110 model reply', () async {
    final h = PrinterHarness()..shortModel = true;
    await h.session.identify();
    await h.session.print(Uint8List(96), 1);
    expect(h.commands.last.command, 0xf3);
  });

  test(
    'a transport error after an early ACK still fails identification',
    () async {
      late NiimbotSession session;
      session = NiimbotSession(
        write: (bytes) async {
          session.receive(NiimbotPacket(0xc2, [1]).encode());
          throw StateError('Write failed after early notification');
        },
      );
      await expectLater(session.identify(), throwsStateError);
    },
  );

  test(
    'timeout never retries and late replies cannot unlock the failed session',
    () async {
      final h = PrinterHarness()..silent = 0x03;
      await h.session.identify();
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      final count = h.commands.length;
      h.session.receive(NiimbotPacket(0x04, [1]).encode());
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands, hasLength(count));
      expect(h.commands.where((p) => p.command == 0x03), hasLength(1));
      expect(h.commands.any((p) => p.command == 0xf3), isFalse);
    },
  );

  test(
    'paper errors and disconnects stop the job before bitmap data',
    () async {
      for (final disconnect in [false, true]) {
        final h = PrinterHarness();
        if (disconnect) {
          h.lose = 0x13;
        } else {
          h.reject = 0x13;
        }
        await h.session.identify();
        await expectLater(
          h.session.print(Uint8List(96), 1),
          throwsA(isA<LabelPrintException>()),
        );
        expect(h.commands.last.command, 0x13);
      }
    },
  );

  test(
    'completion polling is bounded and a busy job cannot be submitted twice',
    () async {
      final h = PrinterHarness()..neverFinish = true;
      await h.session.identify();
      h.holdRows = Completer<void>();
      final first = h.session.print(Uint8List(96), 1);
      final checked = expectLater(first, throwsA(isA<LabelPrintException>()));
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      h.holdRows!.complete();
      await checked;
      expect(h.commands.where((p) => p.command == 0x01), hasLength(1));
    },
  );
}
