import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_niimbot_ble_platform.dart';
import 'niimbot_session_test.dart' show PrinterHarness;

void main() {
  const model = LabelPrinterModel.d11H;
  const device = FoundDevice(id: 'D11_H-TEST', name: 'D11_H-TEST');
  late Directory directory;
  late FakeNiimbotBlePlatform platform;
  late NiimbotLabelPrinter printer;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('niimbot-d11h-');
    platform = FakeNiimbotBlePlatform()..model = 528;
    UniversalBle.setInstance(platform);
    printer = NiimbotLabelPrinter(
      PairedDeviceFile(File(path.join(directory.path, 'd11h.json'))),
      model: model,
    );
  });
  tearDown(() async {
    await printer.stopSearch();
    await printer.disconnect();
    printer.dispose();
    await directory.delete(recursive: true);
  });

  test('discovers D11_H and verifies identity before remembering it', () async {
    await printer.search();
    expect(printer.found.map((d) => d.name), ['D11-TEST', 'D11_H-TEST']);
    await printer.pair(printer.found.last);
    expect(printer.connected, isTrue);
    expect(platform.commands.map((p) => p.command), [0xc1, 0xa5, 0x40]);
    expect((await printer.store.load())?.name, device.name);
    expect(printer.diagnosticReport, contains('"id":528'));
    expect(printer.diagnosticReport, contains('"protocolVersion":5'));
    for (final name in ['D11-H-123', 'D11 H-123', 'D11H-123']) {
      expect(model.matchesName(name), isTrue);
    }
    for (final name in ['D110-X', 'D110_M-X', 'D11S-X', 'D11_PRO-X', null]) {
      expect(model.matchesName(name), isFalse);
    }
  });

  for (final id in [512, 531, 2304]) {
    test('rejects another identity $id even under a D11_H name', () async {
      platform.model = id;
      await printer.pair(device);
      expect(printer.connected, isFalse);
      expect(await printer.store.load(), isNull);
      expect(platform.commands.map((p) => p.command), [0xc1, 0xa5, 0x40]);
    });
  }

  test('short identity cannot mistake D11-H for the original D11', () async {
    platform.shortModel = true;
    await printer.pair(device);
    expect(printer.connected, isFalse);
    expect(await printer.store.load(), isNull);
  });

  for (final revision in [204, 400, null]) {
    test('rejects unsupported or truncated protocol $revision', () async {
      platform.revision = revision ?? 302;
      platform.shortStatus = revision == null;
      await printer.pair(device);
      expect(printer.connected, isFalse);
      expect(platform.commands.where((p) => p.command == 0x01), isEmpty);
    });
  }

  for (final revision in [300, 302]) {
    test(
      'rotated 300 dpi raster uses V4 page header for revision $revision',
      () async {
        final h = PrinterHarness(profile: model)..revision = revision;
        await h.session.identify();
        await h.session.print(Uint8List(144 * 2)..[143 * 2] = 1, 2, copies: 2);
        expect(h.commands.map((p) => p.command), [
          0xc1,
          0xa5,
          0x40,
          0x23,
          0x21,
          0x01,
          0xa3,
          0x13,
          0x85,
          0x84,
          0xe3,
          0xa3,
          0xf3,
        ]);
        expect(h.commands.singleWhere((p) => p.command == 0x13).payload, [
          0,
          2,
          0,
          144,
          0,
          2,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        expect(
          h.commands.singleWhere((p) => p.command == 0x85).payload.take(7),
          [0, 0, 1, 0, 0, 1, 128],
        );
      },
    );
  }

  test('every paper raster packs to whole bytes without stretching', () {
    for (final paper in model.papers) {
      final pixels = Uint8List(paper.printableHeight * paper.printableWidth)
        ..fillRange(0, paper.printableHeight * paper.printableWidth, 1);
      final rows = niimbotImageRows(pixels, paper.printableWidth, model: model);
      expect(rows.length, paper.feedPixels);
      expect(rows.first.payload.length, 24);
      expect(
        rows.first.payload.sublist(2, 5),
        paper.widthMm == 12 ? [48, 48, 46] : [48, 48, 48],
      );
      expect(rows.first.payload.last, paper.widthMm == 12 ? 252 : 255);
    }
  });

  for (final mtu in <int?>[23, 64, 247, null]) {
    test(
      'row batches respect negotiated MTU $mtu and complete the job',
      () async {
        platform.negotiatedMtu = mtu ?? 23;
        platform.failMtu = mtu == null;
        await printer.pair(device);
        expect(printer.connected, isTrue);
        final paper = model.defaultPaper;
        final pixels = Uint8List(paper.printableHeight * paper.printableWidth)
          ..fillRange(0, paper.printableHeight * paper.printableWidth, 1);
        final start = platform.chunks.length;
        await printer.printLabel(pixels, paper);
        final writes = platform.chunks.skip(start).toList();
        final limit = ((mtu ?? 23) - 3).clamp(20, 240);
        expect(writes.every((w) => w.length <= limit), isTrue);
        if (mtu == 247 || mtu == 64) {
          if (mtu == 247) {
            expect(
              writes.any((w) => NiimbotDecoder().add(w).length > 1),
              isTrue,
            );
          }
          expect(
            writes.every((w) => NiimbotDecoder().add(w).isNotEmpty),
            isTrue,
          );
        }
        expect(
          platform.commands.where((p) => p.command == 0x85).length,
          paper.feedPixels,
        );
        expect(platform.commands.last.command, 0xf3);
        expect(platform.events, contains('mtu:247'));
      },
    );
  }

  for (final failWrite in [true, false]) {
    test(
      'failed or truncated row upload never succeeds or retries: $failWrite',
      () async {
        platform.negotiatedMtu = 247;
        platform.failRows = failWrite;
        platform.receivedRow = failWrite ? null : 0;
        await printer.pair(device);
        final paper = model.defaultPaper;
        await expectLater(
          printer.printLabel(
            Uint8List(paper.printableHeight * paper.printableWidth),
            paper,
          ),
          throwsA(anything),
        );
        expect(printer.connected, isFalse);
        expect(platform.commands.where((p) => p.command == 0x01), hasLength(1));
        expect(platform.commands.where((p) => p.command == 0xf3), isEmpty);
        final count = platform.commands.length;
        await expectLater(
          printer.printLabel(
            Uint8List(paper.printableHeight * paper.printableWidth),
            paper,
          ),
          throwsA(isA<LabelPrintException>()),
        );
        expect(platform.commands.length, count);
      },
    );
  }

  test('D11-H paper preference is independent of D11 and D110', () async {
    final file = File(path.join(directory.path, 'paper.json'));
    final settings = LabelOutputPreferences(file);
    await settings.remember(LabelPaper.mm15x50);
    await settings.remember(const LabelPaper(15, 40, LabelPrinterModel.d11));
    await settings.remember(const LabelPaper(12, 40, model));
    final reopened = LabelOutputPreferences(file);
    await reopened.load();
    expect(reopened.model, model);
    expect(reopened.paperFor(model), const LabelPaper(12, 40, model));
    expect(
      reopened.paperFor(LabelPrinterModel.d11),
      const LabelPaper(15, 40, LabelPrinterModel.d11),
    );
    expect(reopened.paperFor(LabelPrinterModel.d110), LabelPaper.mm15x50);
  });
}
