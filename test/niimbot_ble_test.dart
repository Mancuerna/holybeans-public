import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:path/path.dart' as path;
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_niimbot_ble_platform.dart';

void main() {
  for (final mtu in [23, 247, null]) {
    test('B1 Pro identifies after best-effort MTU negotiation: $mtu', () async {
      final platform = FakeNiimbotBlePlatform()
        ..model = 4097
        ..negotiatedMtu = mtu ?? 23
        ..failMtu = mtu == null;
      UniversalBle.setInstance(platform);
      final directory = await Directory.systemTemp.createTemp('niimbot-mtu-');
      final printer = NiimbotLabelPrinter(
        PairedDeviceFile(File(path.join(directory.path, 'pro.json'))),
        model: LabelPrinterModel.b1Pro,
      );
      try {
        await printer.pair(const FoundDevice(id: 'B1-TEST', name: 'B1-TEST'));
        expect(printer.connected, isTrue);
        expect(platform.events.take(6), [
          'connect',
          'subscribe',
          'mtu:247',
          'command:193',
          'command:165',
          'command:64',
        ]);
        expect(
          printer.diagnosticReport,
          contains(mtu == null ? 'niimbot.mtu.error' : '"mtu":$mtu'),
        );
        expect(platform.commands.map((p) => p.command), [0xc1, 0xa5, 0x40]);
        expect(printer.diagnosticReport, contains('niimbot.writeComplete'));
      } finally {
        await printer.disconnect();
        printer.dispose();
        await directory.delete(recursive: true);
      }
    });
  }
  test(
    'Pro reports the failed handshake stage and does not reconnect itself',
    () async {
      final platform = FakeNiimbotBlePlatform()
        ..model = 4097
        ..reject = 0xa5;
      UniversalBle.setInstance(platform);
      final directory = await Directory.systemTemp.createTemp(
        'niimbot-report-',
      );
      final printer = NiimbotLabelPrinter(
        PairedDeviceFile(File(path.join(directory.path, 'pro.json'))),
        model: LabelPrinterModel.b1Pro,
      );
      try {
        await printer.pair(const FoundDevice(id: 'B1-TEST', name: 'B1-TEST'));
        expect(printer.status, DeviceStatus.failed);
        expect(platform.events.where((e) => e == 'connect'), hasLength(1));
        expect(platform.commands.map((p) => p.command), [0xc1, 0xa5]);
        expect(printer.diagnosticReport, contains('subscribe.ok'));
        expect(printer.diagnosticReport, isNot(contains('"command":64')));
        expect(printer.diagnosticReport, contains('"command":165'));
        expect(printer.diagnosticReport, contains('rejected'));
        expect(printer.diagnosticReport, isNot(contains('B1-TEST')));
        expect(await printer.store.load(), isNull);
      } finally {
        await printer.disconnect();
        printer.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Pro splits full rows at minimum MTU and rejects another model paper',
    () async {
      final platform = FakeNiimbotBlePlatform()..model = 4097;
      UniversalBle.setInstance(platform);
      final directory = await Directory.systemTemp.createTemp('niimbot-pro-');
      final printer = NiimbotLabelPrinter(
        PairedDeviceFile(File(path.join(directory.path, 'pro.json'))),
        model: LabelPrinterModel.b1Pro,
      );
      try {
        await printer.pair(const FoundDevice(id: 'B1-TEST', name: 'B1-TEST'));
        expect(printer.connected, isTrue);
        final before = platform.commands.length;
        await expectLater(
          printer.printLabel(
            Uint8List(576 * 354),
            LabelPrinterModel.b2Pro.defaultPaper,
          ),
          throwsA(isA<LabelPrintException>()),
        );
        expect(platform.commands, hasLength(before));
        await printer.printLabel(
          Uint8List(576 * 354)..fillRange(0, 576, 1),
          LabelPrinterModel.b1Pro.defaultPaper,
          copies: 2,
        );
        expect(
          platform.commands.where((p) => p.command == 0x85).single.payload,
          hasLength(78),
        );
        expect(platform.chunks.every((c) => c.length <= 20), isTrue);
        expect(platform.copies, 2);
        expect(platform.commands.last.command, 0xf3);
      } finally {
        await printer.disconnect();
        printer.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test('B2 firmware must be recognized before pairing is remembered', () async {
    final platform = FakeNiimbotBlePlatform()
      ..model = 6913
      ..revision = 204;
    UniversalBle.setInstance(platform);
    final directory = await Directory.systemTemp.createTemp('niimbot-b2-');
    final printer = NiimbotLabelPrinter(
      PairedDeviceFile(File(path.join(directory.path, 'b2.json'))),
      model: LabelPrinterModel.b2,
    );
    try {
      const device = FoundDevice(id: 'B2-TEST', name: 'B2-TEST');
      await printer.pair(device);
      expect(printer.connected, isFalse);
      expect(await printer.store.load(), isNull);
      expect(platform.commands.map((p) => p.command), [0xc1, 0x40, 0xa5]);
      platform.revision = 302;
      await printer.pair(device);
      expect(printer.connected, isTrue);
      expect((await printer.store.load())?.id, device.id);
    } finally {
      await printer.disconnect();
      printer.dispose();
      await directory.delete(recursive: true);
    }
  });

  late FakeNiimbotBlePlatform platform;
  late D110LabelPrinter printer;
  late Directory directory;
  const device = FoundDevice(id: 'D110-TEST', name: 'D110-TEST');
  setUp(() async {
    platform = FakeNiimbotBlePlatform();
    UniversalBle.setInstance(platform);
    directory = await Directory.systemTemp.createTemp('holybeans-label-ble-');
    printer = D110LabelPrinter(
      PairedDeviceFile(File(path.join(directory.path, 'device.json'))),
    );
  });
  tearDown(() async {
    await printer.stopSearch();
    await printer.disconnect();
    printer.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'B1 scan, remembered device and large rows stay isolated from D110',
    () async {
      final b1 = NiimbotLabelPrinter(
        PairedDeviceFile(File(path.join(directory.path, 'b1.json'))),
        model: LabelPrinterModel.b1,
      );
      try {
        await printer.pair(device);
        await printer.disconnect();
        final scanning = b1.search();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await b1.stopSearch();
        await scanning;
        expect(b1.found.map((d) => d.name), ['B1-TEST']);
        platform.model = 4096;
        await b1.pair(const FoundDevice(id: 'B1-TEST', name: 'B1-TEST'));
        expect(b1.connected, isTrue);
        final before = platform.commands.length;
        await expectLater(
          b1.printLabel(Uint8List(240 * 96), LabelPaper.mm15x30),
          throwsA(isA<LabelPrintException>()),
        );
        expect(platform.commands, hasLength(before));
        final pixels = Uint8List(384 * 240)..fillRange(0, 384, 1);
        await b1.printLabel(pixels, LabelPaper.mm50x30, copies: 2);
        expect(platform.chunks.every((chunk) => chunk.length <= 20), isTrue);
        expect(
          platform.commands.where((p) => p.command == 0x85).single.payload,
          hasLength(54),
        );
        expect(platform.copies, 2);
        expect(platform.commands.last.command, 0xf3);
        await b1.forget();
        expect(await b1.store.load(), isNull);
        expect((await printer.store.load())?.id, device.id);
      } finally {
        await b1.stopSearch();
        await b1.disconnect();
        b1.dispose();
      }
    },
  );

  test(
    'subscribes and identifies before printing; frames fit the minimum MTU',
    () async {
      await printer.pair(device);
      expect(printer.connected, isTrue);
      expect(platform.events.take(4), [
        'connect',
        'subscribe',
        'command:193',
        'command:64',
      ]);
      final pixels = Uint8List(240 * 96);
      for (var y = 0; y < 96; y++) {
        pixels[y * 240] = 1;
      }
      await printer.printLabel(pixels, LabelPaper.mm15x30);
      expect(platform.chunks.every((chunk) => chunk.length <= 20), isTrue);
      expect(
        platform.commands.where((p) => p.command == 0x85).single.payload,
        hasLength(18),
      );
      expect(platform.commands.last.command, 0xf3);
      expect((await printer.store.load())?.id, device.id);
    },
  );
  test(
    'mismatching identity or GATT cannot be remembered or printed',
    () async {
      platform.model = 2320;
      await printer.pair(device);
      expect(printer.connected, isFalse);
      expect(await printer.store.load(), isNull);
      expect(platform.commands.map((p) => p.command), [0xc1, 0x40]);
      platform.commands.clear();
      platform.validServices = false;
      await printer.pair(device);
      expect(platform.commands, isEmpty);
    },
  );
  test('a print error disconnects and requires manual reconnection', () async {
    await printer.pair(device);
    platform.reject = 0x13;
    await expectLater(
      printer.printLabel(Uint8List(240 * 96), LabelPaper.mm15x30),
      throwsA(isA<LabelPrintException>()),
    );
    expect(printer.connected, isFalse);
    expect(printer.printing, isFalse);
    expect(platform.commands.last.command, 0x13);
    expect(platform.events.last, 'disconnect');
  });
}
