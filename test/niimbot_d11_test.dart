import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_identity.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_niimbot_ble_platform.dart';
import 'niimbot_session_test.dart' show PrinterHarness;

void main() {
  test(
    'D11 discovery and identity exclude D110 and newer D11 variants',
    () async {
      final platform = FakeNiimbotBlePlatform()..model = 512;
      UniversalBle.setInstance(platform);
      final directory = await Directory.systemTemp.createTemp('niimbot-d11-');
      final printer = NiimbotLabelPrinter(
        PairedDeviceFile(File(path.join(directory.path, 'd11.json'))),
        model: LabelPrinterModel.d11,
      );
      try {
        await printer.search();
        expect(printer.found.map((d) => d.name), ['D11-TEST']);
        await printer.pair(printer.found.single);
        expect(printer.connected, isTrue);
        expect(platform.commands.map((p) => p.command), [0xc1, 0x40]);
        expect(printer.diagnosticReport, contains('"payload":[2,0]'));
      } finally {
        await printer.stopSearch();
        await printer.disconnect();
        printer.dispose();
        await directory.delete(recursive: true);
      }
      for (final name in ['D110-X', 'D11_H-X', 'D11 Pro-X', 'D11S-X', null]) {
        expect(LabelPrinterModel.d11.matchesName(name), isFalse);
      }
      for (final id in [528, 531, 514, 2304, 2305]) {
        expect(
          () => NiimbotIdentity.resolve(
            LabelPrinterModel.d11,
            id,
            protocolVersion: 0,
          ),
          throwsFormatException,
        );
      }
    },
  );

  for (final hello in [1, 2]) {
    test('D11 greeting $hello selects page format and completion', () async {
      final h = PrinterHarness(profile: LabelPrinterModel.d11)
        ..hello = hello
        ..legacyPage = [0, 2];
      await h.session.identify();
      final pixels = Uint8List(96 * 2)..[95 * 2] = 1;
      await h.session.print(pixels, 2, copies: 2);
      expect(h.commands.map((p) => p.command), [
        0xc1,
        0x40,
        0x21,
        0x23,
        0x01,
        0x20,
        0x03,
        0x13,
        0x15,
        0x85,
        0x84,
        0xe3,
        if (hello == 2) 0xa3,
        0xf3,
      ]);
      expect(
        h.commands.singleWhere((p) => p.command == 0x13).payload,
        hello == 1 ? [0, 2] : [0, 2, 0, 96],
      );
      expect(h.commands.singleWhere((p) => p.command == 0x15).payload, [0, 2]);
      final row = h.commands.singleWhere((p) => p.command == 0x85).payload;
      expect(row.take(7), [0, 0, 1, 0, 0, 1, 0x80]);
      expect(row.length, 18);
    });
  }

  test(
    'D11 newer greeting is rejected without guessing or sending a job',
    () async {
      final h = PrinterHarness(profile: LabelPrinterModel.d11)..hello = 3;
      await expectLater(
        h.session.identify(),
        throwsA(isA<LabelPrintException>()),
      );
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands.map((p) => p.command), [0xc1]);
    },
  );

  for (final page in <List<int>?>[
    null,
    [0, 1],
    [2],
  ]) {
    test('legacy D11 requires all copies and valid E0: $page', () async {
      final h = PrinterHarness(profile: LabelPrinterModel.d11)
        ..legacyPage = page;
      await h.session.identify();
      await expectLater(
        h.session.print(Uint8List(96), 1, copies: 2),
        throwsA(isA<LabelPrintException>()),
      );
      final count = h.commands.length;
      h.session.receive(NiimbotPacket(0xe0, [0, 2]).encode());
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands.length, count);
      expect(
        h.commands.where((p) => p.command == 0xa3 || p.command == 0xf3),
        isEmpty,
      );
      expect(h.commands.where((p) => p.command == 0x01), hasLength(1));
    });
  }

  test(
    'legacy D11 accepts delayed E0 but resets progress for next job',
    () async {
      final h = PrinterHarness(profile: LabelPrinterModel.d11);
      await h.session.identify();
      final timer = Timer(const Duration(milliseconds: 10), () {
        h.session.receive(NiimbotPacket(0xe0, [0, 1]).encode());
      });
      addTearDown(timer.cancel);
      await h.session.print(Uint8List(96), 1);
      await expectLater(
        h.session.print(Uint8List(96), 1),
        throwsA(isA<LabelPrintException>()),
      );
      expect(h.commands.where((p) => p.command == 0xf3), hasLength(1));
    },
  );
}
