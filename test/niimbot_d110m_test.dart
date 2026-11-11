import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_identity.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_niimbot_ble_platform.dart';
import 'niimbot_session_test.dart' show PrinterHarness;

void main() {
  const model = LabelPrinterModel.d110M;

  test('recognizes D110_M names without treating them as original D110', () {
    for (final name in ['D110_M-I123456789', 'D110M-X', 'd110_m', 'D110 M-X']) {
      expect(model.matchesName(name), isTrue);
      expect(LabelPrinterModel.d110.matchesName(name), isFalse);
    }
    for (final name in ['D110-X', 'D11-X', 'D110_MPro-X', 'B1-X', null]) {
      expect(model.matchesName(name), isFalse);
    }
    expect(model.defaultPaper.printableWidth, 240);
    expect(model.defaultPaper.printableHeight, 96);
    expect(model.defaultDensity, 3);
  });

  // Match NiimBlueLib's explicit protocol-4 override, including the B1
  // default for protocol 5. Firmware 4.31 must not be treated as protocol 4.
  for (final (hello, revision, protocol, v4) in [
    (1, 0, 0, false),
    (2, 0, 1, false),
    (3, 204, 3, false),
    (3, 301, 4, true),
    (3, 302, 5, false),
  ]) {
    test('negotiates protocol $protocol and prints rotated copies', () async {
      final h = PrinterHarness(profile: model)
        ..hello = hello
        ..revision = revision;
      await h.session.identify();
      expect(h.session.identity!.id, 2320);
      expect(h.session.identity!.protocolVersion, protocol);
      expect(
        h.session.identity!.family,
        v4 ? NiimbotPrintFamily.v4 : NiimbotPrintFamily.b1,
      );
      expect(h.commands.map((p) => p.command), [
        0xc1,
        if (hello == 3) 0xa5,
        0x40,
      ]);
      await h.session.print(Uint8List(96 * 2)..[95 * 2] = 1, 2, copies: 2);
      expect(
        h.commands.firstWhere((p) => p.command == 0x01).payload,
        v4 ? [0, 2, 0, 0, 0, 0, 0, 1, 0] : [0, 2, 0, 0, 0, 0, 0],
      );
      expect(
        h.commands.firstWhere((p) => p.command == 0x13).payload,
        v4 ? [0, 2, 0, 96, 0, 2, 0, 0, 0, 0, 0, 0, 0] : [0, 2, 0, 96, 0, 2],
      );
      final row = h.commands.firstWhere((p) => p.command == 0x85);
      expect(row.payload.take(7), [0, 0, 1, 0, 0, 1, 128]);
      expect(row.payload, hasLength(18));
      expect(h.commands.map((p) => p.command).toList().reversed.take(3), [
        0xf3,
        0xa3,
        0xe3,
      ]);
      expect(
        h.commands.where((p) => p.command == 0x20 || p.command == 0x15),
        isEmpty,
      );
    });
  }

  for (final revision in [0, 203, 400]) {
    test(
      'unknown status revision $revision cannot authorize printing',
      () async {
        final h = PrinterHarness(profile: model)
          ..hello = 3
          ..revision = revision;
        await expectLater(
          h.session.identify(),
          throwsA(isA<LabelPrintException>()),
        );
        await expectLater(
          h.session.print(Uint8List(96), 1),
          throwsA(isA<LabelPrintException>()),
        );
        expect(h.commands.map((p) => p.command), [0xc1, 0xa5]);
      },
    );
  }

  group('BLE discovery and identity', () {
    late Directory directory;
    late FakeNiimbotBlePlatform platform;
    late NiimbotLabelPrinter printer;
    const device = FoundDevice(id: 'D110M-TEST', name: 'D110_M-TEST');
    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      directory = await Directory.systemTemp.createTemp('niimbot-d110m-');
      platform = FakeNiimbotBlePlatform()
        ..model = 2320
        ..hello = 3
        ..revision = 301;
      UniversalBle.setInstance(platform);
      printer = NiimbotLabelPrinter(
        PairedDeviceFile(File.fromUri(directory.uri.resolve('printer.json'))),
        model: model,
      );
    });
    tearDown(() async {
      await printer.stopSearch();
      await printer.disconnect();
      printer.dispose();
      debugDefaultTargetPlatformOverride = null;
      await directory.delete(recursive: true);
    });

    test(
      'discovers, identifies, remembers and prints over minimum MTU',
      () async {
        await printer.search();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(printer.found.map((d) => d.name), [device.name]);
        await printer.pair(printer.found.single);
        expect(printer.connected, isTrue);
        expect(platform.events, contains('mtu:247'));
        expect((await printer.store.load())?.name, device.name);
        expect(printer.diagnosticReport, contains('"id":2320'));
        expect(printer.diagnosticReport, contains('scan.start'));
        expect(printer.diagnosticReport, contains('"supportedDevices":1'));
        expect(printer.diagnosticReport, isNot(contains(device.name)));
        final paper = model.defaultPaper;
        await printer.printLabel(
          Uint8List(paper.printableWidth * paper.printableHeight)..[0] = 1,
          paper,
        );
        expect(platform.chunks.every((chunk) => chunk.length <= 20), isTrue);
        expect(platform.commands.last.command, 0xf3);
      },
    );

    test(
      'MTU negotiation failure still permits fragmented identification',
      () async {
        platform.failMtu = true;
        await printer.pair(device);
        expect(printer.connected, isTrue);
        expect(printer.diagnosticReport, contains('niimbot.mtu.error'));
        expect(platform.chunks.every((chunk) => chunk.length <= 20), isTrue);
      },
    );

    for (final id in [2304, 2305, 4096]) {
      test('rejects model $id advertised under a D110_M name', () async {
        platform.model = id;
        await printer.pair(device);
        expect(printer.connected, isFalse);
        expect(await printer.store.load(), isNull);
        expect(platform.commands.map((p) => p.command), [0xc1, 0xa5, 0x40]);
      });
    }

    test('rejects truncated status before remembering or printing', () async {
      platform.shortStatus = true;
      await printer.pair(device);
      expect(printer.connected, isFalse);
      expect(await printer.store.load(), isNull);
      expect(platform.commands.map((p) => p.command), [0xc1, 0xa5]);
    });

    test(
      'truncated model ID cannot be mistaken for the original D110',
      () async {
        platform.shortModel = true;
        await printer.pair(device);
        expect(printer.connected, isFalse);
        expect(await printer.store.load(), isNull);
      },
    );
  });
}
