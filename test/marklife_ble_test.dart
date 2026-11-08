import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/marklife_printer.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/marklife_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_marklife_ble_platform.dart';

void main() {
  late FakeMarklifeBlePlatform platform;
  late MarklifePrinter printer;
  late Directory directory;
  late PairedDeviceFile store;
  final paper = LabelPrinterModel.marklifeP12.defaultPaper;
  const device = FoundDevice(id: 'PRIVATE-ADDRESS', name: 'P12_PRIVATE_BLE');
  setUp(() async {
    platform = FakeMarklifeBlePlatform()..negotiatedMtu = 247;
    UniversalBle.setInstance(platform);
    directory = await Directory.systemTemp.createTemp('marklife-test-');
    store = PairedDeviceFile(File('${directory.path}/paired.json'));
    printer = MarklifePrinter(store);
  });
  tearDown(() async {
    await printer.disconnect();
    printer.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'scan only lists P12 and connecting subscribes without printing',
    () async {
      await printer.search();
      await Future<void>.delayed(Duration.zero);
      await printer.stopSearch();
      expect(printer.found.map((d) => d.name), ['P12_TEST_BLE']);
      await printer.pair(device);
      expect(printer.connected, isTrue);
      expect(platform.chunks, isEmpty);
      expect(
        platform.events,
        containsAllInOrder([
          'connect',
          'subscribe:${MarklifeProtocol.rx}',
          'subscribe:${MarklifeProtocol.control}',
          'mtu:247',
        ]),
      );
      expect(printer.diagnosticReport, isNot(contains('PRIVATE')));
    },
  );
  test(
    'missing flow-control characteristic rejects before all writes',
    () async {
      platform.hasControl = false;
      await printer.pair(device);
      expect(printer.status, DeviceStatus.failed);
      expect(platform.chunks, isEmpty);
      expect(printer.diagnosticReport, contains('"control":false'));
    },
  );
  test(
    'unrelated advertised model is rejected despite matching services',
    () async {
      await printer.pair(const FoundDevice(id: 'OTHER', name: 'P15_TEST'));
      expect(printer.status, DeviceStatus.failed);
      expect(platform.chunks, isEmpty);
    },
  );
  test(
    'single manual print uses 90-byte cap and keeps private data out of log',
    () async {
      await printer.pair(device);
      await printer.printLabel(Uint8List(320 * 96), paper);
      expect(platform.chunks.every((c) => c.length <= 90), isTrue);
      expect(
        platform.received,
        MarklifeProtocol.job(Uint8List(320 * 96), 40, MarklifePaper.continuous),
      );
      expect(printer.diagnosticReport, contains('marklife.accepted'));
      expect(printer.diagnosticReport, isNot(contains('PRIVATE')));
      expect(printer.printing, isFalse);
    },
  );
  test('MTU failure keeps 20-byte payload; uncertain write disconnects with no retry', () async {
    platform.failMtu = true;
    platform.failAtChunk = 2;
    await printer.pair(device);
    await expectLater(
      printer.printLabel(Uint8List(320 * 96), paper, copies: 3),
      throwsStateError,
    );
    expect(platform.chunks, hasLength(2));
    expect(platform.chunks.every((c) => c.length <= 20), isTrue);
    expect(printer.connected, isFalse);
    expect(platform.events.where((e) => e == 'connect'), hasLength(1));
    expect(printer.diagnosticReport, contains('"reason":"transport"'));
  });
  test('remembers only a P12 and forgetting removes the pairing', () async {
    await store.save(const FoundDevice(id: 'other', name: 'D110-TEST'));
    await printer.load();
    expect(printer.name, isNull);
    await printer.pair(device);
    await printer.disconnect();
    final reopened = MarklifePrinter(store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.name, device.name);
    expect(reopened.connected, isFalse);
    await reopened.forget();
    expect(await store.load(), isNull);
    expect(platform.chunks, isEmpty);
  });
  test(
    'copies send complete continuous jobs only after acknowledgement',
    () async {
      await printer.pair(device);
      final pixels = Uint8List(320 * 96);
      await printer.printLabel(pixels, paper, copies: 2);
      final job = MarklifeProtocol.job(pixels, 40, MarklifePaper.continuous);
      expect(platform.received, [...job, ...job]);
      expect(
        RegExp('marklife.accepted').allMatches(printer.diagnosticReport),
        hasLength(2),
      );
    },
  );
  test('invalid media, pixels and copies never write or disconnect', () async {
    await printer.pair(device);
    for (final (candidate, pixels, copies) in [
      (LabelPaper.mm15x40, Uint8List(320 * 96), 1),
      (
        const LabelPaper(12, 40, LabelPrinterModel.marklifeP12),
        Uint8List(320 * 96),
        1,
      ),
      (paper, Uint8List(1), 1),
      (paper, Uint8List(320 * 96)..[0] = 2, 1),
      (paper, Uint8List(320 * 96), 0),
      (paper, Uint8List(320 * 96), 11),
    ]) {
      await expectLater(
        printer.printLabel(pixels, candidate, copies: copies),
        throwsA(isA<MarklifeException>()),
      );
    }
    expect(platform.chunks, isEmpty);
    expect(printer.connected, isTrue);
  });
  test('diagnostic keeps a bounded log without arbitrary error strings', () {
    for (var i = 0; i < 300; i++) {
      printer.traceEvent('connect.error', {
        'error': 'private label and address',
      });
    }
    expect(printer.diagnosticReport.split('\n'), hasLength(202));
    expect(printer.diagnosticReport, isNot(contains('private label')));
  });
}
