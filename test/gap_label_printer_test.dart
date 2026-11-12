import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/gap_label_printer.dart';
import 'package:holybeans/data/services/marklife_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/gap_printer_protocol.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/marklife_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_marklife_ble_platform.dart';

class GapPlatform extends FakeMarklifeBlePlatform {
  bool acknowledge = true;
  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    for (final name in [
      'P15_TEST',
      'P150',
      'P12_TEST',
      'FICHERO_5836',
      'FICHERO_58360',
    ]) {
      updateScanResult(BleDevice(deviceId: name, name: name));
    }
  }

  final sent = Completer<void>();
  String? id;
  String get notifyCharacteristic => MarklifeProtocol.rx;

  void reply(List<int> bytes) => updateCharacteristicValue(
    id!,
    notifyCharacteristic,
    Uint8List.fromList(bytes),
    null,
  );

  void finish(String deviceId) {
    id = deviceId;
    if (received.length >= 4 &&
        received.sublist(received.length - 4).join(',') == '16,255,254,69') {
      if (!sent.isCompleted) sent.complete();
      if (acknowledge) reply([0xaa]);
    }
  }

  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty property,
  ) async {
    await super.writeValue(id, service, characteristic, value, property);
    finish(id);
  }
}

class UartPlatform extends GapPlatform {
  static const uartService = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static const rx = '49535343-1e4d-4bd9-ba61-23c647249616';
  static const tx = '49535343-8841-43f4-a8d4-ecbe34729bb3';
  @override
  String get notifyCharacteristic => rx;
  @override
  Future<List<BleService>> discoverServices(
    String id,
    bool descriptors,
  ) async => [
    BleService(uartService, [
      BleCharacteristic(rx, [CharacteristicProperty.notify], []),
      BleCharacteristic(tx, [
        CharacteristicProperty.write,
        CharacteristicProperty.writeWithoutResponse,
      ], []),
    ]),
  ];
  @override
  Future<void> writeValue(
    String id,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty property,
  ) async {
    expect(service, uartService);
    expect(characteristic, tx);
    expect(property, BleOutputProperty.withResponse);
    chunks.add(Uint8List.fromList(value));
    if (chunks.length == failAtChunk) {
      throw StateError('PRIVATE device disconnected');
    }
    received.addAll(value);
    finish(id);
  }
}

void main() {
  test(
    'models filter names without accepting lookalikes or other printers',
    () {
      expect(GapPrinterModel.p15.matchesName('P15_TEST'), isTrue);
      expect(GapPrinterModel.p15.matchesName('Pristar P15'), isTrue);
      expect(GapPrinterModel.fichero.matchesName('FICHERO_5836'), isTrue);
      for (final name in [null, 'P150', 'P12_TEST', 'D110', 'FICHERO_58360']) {
        expect(GapPrinterModel.values.any((m) => m.matchesName(name)), isFalse);
      }
    },
  );
  for (final length in [30, 40]) {
    test(
      'independent AiYin job has rotated raster and gap alignment ($length)',
      () {
        final pixels = Uint8List(length * 8 * 96)..[0] = 1;
        final bytes = GapPrinterModel.fichero.job(
          pixels,
          length,
          MarklifePaper.gap,
        );
        expect(bytes.take(16), [...List.filled(12, 0), 0x10, 0xff, 0xfe, 1]);
        expect(bytes.sublist(16, 24), [
          0x1d,
          0x76,
          0x30,
          0,
          12,
          0,
          length * 8 & 255,
          length * 8 >> 8,
        ]);
        expect(bytes[24 + 11], 1);
        expect(bytes.sublist(24, bytes.length - 6).where((v) => v != 0), [1]);
        expect(bytes.sublist(bytes.length - 6), [
          0x1d,
          0x0c,
          0x10,
          0xff,
          0xfe,
          0x45,
        ]);
        expect(bytes.length, length * 8 * 12 + 30);
        expect(
          GapPrinterModel.p15.job(pixels, length, MarklifePaper.gap),
          MarklifeProtocol.job(pixels, length, MarklifePaper.gap),
        );
      },
    );
  }
  test('reject invalid media, lengths and raster before transmission', () {
    for (final model in GapPrinterModel.values) {
      for (final length in [14, 35, 50]) {
        expect(
          () =>
              model.job(Uint8List(length * 8 * 96), length, MarklifePaper.gap),
          throwsA(isA<MarklifeException>()),
        );
      }
      expect(
        () => model.job(Uint8List(30 * 8 * 96), 30, MarklifePaper.continuous),
        throwsA(isA<MarklifeException>()),
      );
      expect(
        () => model.job(Uint8List(1), 30, MarklifePaper.gap),
        throwsA(isA<MarklifeException>()),
      );
    }
  });
  test('AiYin decodes its bitmask and only complete acknowledgements', () {
    for (final entry in {
      1: MarklifeFailure.hot,
      2: MarklifeFailure.cover,
      4: MarklifeFailure.paper,
      8: MarklifeFailure.battery,
      5: MarklifeFailure.hot,
    }.entries) {
      expect(
        GapPrinterModel.ficheroError(Uint8List.fromList([0xff, entry.key])),
        entry.value,
      );
    }
    for (final bytes in [
      [0xaa],
      [0x4f, 0x4b],
    ]) {
      expect(GapPrinterModel.ficheroAck(Uint8List.fromList(bytes)), isTrue);
    }
    for (final bytes in <List<int>>[
      [],
      [0x4f],
      [0x4b],
      [0xff, 4],
      [0xaa, 0],
    ]) {
      expect(GapPrinterModel.ficheroAck(Uint8List.fromList(bytes)), isFalse);
    }
  });
  for (final reply in <List<int>>[
    [],
    [0x4f],
    [0xff, 4],
  ]) {
    test(
      'AiYin session rejects missing/partial/error replies: $reply',
      () async {
        final bytes = <int>[];
        late final MarklifeSession session;
        session = MarklifeSession(
          write: (value) async {
            bytes.addAll(value);
            // An unsolicited/early success must not acknowledge this job.
            if (bytes.length == value.length) {
              session.receive(Uint8List.fromList([0xaa]));
            }
            if (bytes.length == 2910 && reply.isNotEmpty) {
              session.receive(Uint8List.fromList(reply));
            }
          },
          encodeJob: GapPrinterModel.fichero.job,
          requiresCredits: false,
          responseFailure: GapPrinterModel.ficheroError,
          acknowledgement: GapPrinterModel.ficheroAck,
          resultTimeout: const Duration(milliseconds: 20),
          packetDelay: Duration.zero,
        );
        final pixels = Uint8List(30 * 8 * 96);
        await expectLater(
          session.print(pixels, 30, MarklifePaper.gap),
          throwsA(
            isA<MarklifeException>().having(
              (e) => e.failure,
              'reason',
              reply.length == 2
                  ? MarklifeFailure.paper
                  : MarklifeFailure.unconfirmed,
            ),
          ),
        );
        expect(bytes.length, 2910);
        await expectLater(
          session.print(pixels, 30, MarklifePaper.gap),
          throwsA(isA<MarklifeException>()),
        );
        expect(bytes.length, 2910);
      },
    );
  }
  test(
    'Fichero stays connected and busy after sending until a late ACK',
    () async {
      final platform = GapPlatform()
        ..negotiatedMtu = 247
        ..acknowledge = false;
      UniversalBle.setInstance(platform);
      final printer = GapLabelPrinter(GapPrinterModel.fichero);
      addTearDown(() async {
        await printer.disconnect();
        printer.dispose();
      });
      await printer.pair(
        const FoundDevice(id: 'PRIVATE', name: 'FICHERO_5836'),
      );
      var complete = false;
      final pixels = Uint8List(30 * 8 * 96);
      final job = printer
          .printLabel(
            pixels,
            printer.model.papers.firstWhere((p) => p.lengthMm == 30),
          )
          .then((_) => complete = true);
      await platform.sent.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(printer.connected, isTrue);
      expect(printer.printing, isTrue);
      expect(complete, isFalse);
      expect(printer.diagnosticReport, contains('gap.awaitingResult'));
      expect(printer.diagnosticReport, isNot(contains('marklife.accepted')));
      await expectLater(
        printer.printLabel(
          pixels,
          printer.model.papers.firstWhere((p) => p.lengthMm == 30),
        ),
        throwsA(
          isA<MarklifeException>().having(
            (e) => e.failure,
            'reason',
            MarklifeFailure.busy,
          ),
        ),
      );
      platform.reply([0x4f, 0x4b]);
      await job;
      expect(complete, isTrue);
      expect(printer.connected, isTrue);
      expect(printer.printing, isFalse);
      expect(platform.received.length, 2910);
      expect(printer.diagnosticReport, contains('marklife.accepted'));
    },
  );
  test(
    'Fichero missing ACK disconnects only after timeout, never retries',
    () async {
      final platform = GapPlatform()
        ..negotiatedMtu = 247
        ..acknowledge = false;
      UniversalBle.setInstance(platform);
      final printer = GapLabelPrinter(
        GapPrinterModel.fichero,
        ficheroResultTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(printer.dispose);
      await printer.pair(
        const FoundDevice(id: 'PRIVATE', name: 'FICHERO_5836'),
      );
      await expectLater(
        printer.printLabel(
          Uint8List(30 * 8 * 96),
          printer.model.papers.firstWhere((p) => p.lengthMm == 30),
        ),
        throwsA(
          isA<MarklifeException>().having(
            (e) => e.failure,
            'reason',
            MarklifeFailure.unconfirmed,
          ),
        ),
      );
      expect(platform.received.length, 2910);
      expect(printer.connected, isFalse);
      expect(printer.diagnosticReport, contains('"reason":"unconfirmed"'));
      expect(printer.diagnosticReport, isNot(contains('marklife.accepted')));
      expect(platform.events.where((e) => e == 'connect'), hasLength(1));
    },
  );
  for (final model in GapPrinterModel.values) {
    test(
      '${model.name}: connection does not write; manual job uses real credits',
      () async {
        final platform = GapPlatform()..negotiatedMtu = 247;
        UniversalBle.setInstance(platform);
        final printer = GapLabelPrinter(model);
        addTearDown(() async {
          await printer.disconnect();
          printer.dispose();
        });
        await printer.pair(
          FoundDevice(
            id: 'PRIVATE-ADDRESS',
            name: model == GapPrinterModel.p15 ? 'P15_PRIVATE' : 'FICHERO_5836',
          ),
        );
        expect(printer.connected, isTrue);
        expect(platform.chunks, isEmpty);
        final pixels = Uint8List(40 * 8 * 96);
        await printer.printLabel(
          pixels,
          printer.model.papers.firstWhere((p) => p.lengthMm == 40),
        );
        expect(platform.received, model.job(pixels, 40, MarklifePaper.gap));
        expect(platform.chunks.every((c) => c.length <= 90), isTrue);
        expect(printer.connected, isTrue);
        expect(printer.diagnosticReport, isNot(contains('PRIVATE')));
        expect(printer.diagnosticReport, contains('marklife.accepted'));
      },
    );
  }
  test(
    'incomplete credits interface and wrong name cannot send commands',
    () async {
      final platform = FakeMarklifeBlePlatform()..hasControl = false;
      UniversalBle.setInstance(platform);
      final printer = GapLabelPrinter(GapPrinterModel.p15);
      addTearDown(printer.dispose);
      await printer.pair(const FoundDevice(id: 'PRIVATE', name: 'P15_TEST'));
      expect(printer.status, DeviceStatus.failed);
      expect(platform.chunks, isEmpty);
      platform.hasControl = true;
      await printer.pair(const FoundDevice(id: 'PRIVATE', name: 'D110_TEST'));
      expect(printer.status, DeviceStatus.failed);
      expect(platform.chunks, isEmpty);
    },
  );
  for (final fail in [false, true]) {
    test(
      'Fichero UART: 20-byte acknowledged writes, no retry (fail=$fail)',
      () async {
        final platform = UartPlatform()..negotiatedMtu = 247;
        if (fail) platform.failAtChunk = 2;
        UniversalBle.setInstance(platform);
        final printer = GapLabelPrinter(GapPrinterModel.fichero);
        addTearDown(printer.dispose);
        await printer.pair(
          const FoundDevice(id: 'PRIVATE', name: 'FICHERO_5836'),
        );
        expect(printer.connected, isTrue);
        expect(platform.chunks, isEmpty);
        final pixels = Uint8List(30 * 8 * 96);
        if (fail) {
          await expectLater(
            printer.printLabel(
              pixels,
              printer.model.papers.firstWhere((p) => p.lengthMm == 30),
            ),
            throwsStateError,
          );
          expect(platform.chunks, hasLength(2));
        } else {
          await printer.printLabel(
            pixels,
            printer.model.papers.firstWhere((p) => p.lengthMm == 30),
          );
          expect(
            platform.received,
            GapPrinterModel.fichero.job(pixels, 30, MarklifePaper.gap),
          );
        }
        expect(printer.connected, !fail);
        expect(platform.chunks.every((c) => c.length <= 20), isTrue);
        expect(platform.events.where((e) => e == 'connect'), hasLength(1));
        expect(printer.diagnosticReport, isNot(contains('PRIVATE')));
      },
    );
  }
  for (final profile in GapPrinterModel.values) {
    test(
      '${profile.name}: discovery, persistence, validation and copies',
      () async {
        final platform = GapPlatform()..negotiatedMtu = 247;
        UniversalBle.setInstance(platform);
        final directory = await Directory.systemTemp.createTemp(
          'gap-printer-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final store = PairedDeviceFile(
          File(path.join(directory.path, 'paired.json')),
        );
        final printer = GapLabelPrinter(profile, store: store);
        addTearDown(printer.dispose);
        await printer.search();
        await Future<void>.delayed(Duration.zero);
        await printer.stopSearch();
        final name = profile == GapPrinterModel.p15
            ? 'P15_TEST'
            : 'FICHERO_5836';
        expect(printer.found.map((d) => d.name), [name]);
        await printer.pair(printer.found.single);
        expect(platform.chunks, isEmpty);
        final reopened = GapLabelPrinter(profile, store: store);
        addTearDown(reopened.dispose);
        await reopened.load();
        expect(reopened.name, name);
        final paper = printer.model.defaultPaper;
        final pixels = Uint8List(paper.printableWidth * paper.printableHeight);
        for (final copies in [0, 11]) {
          await expectLater(
            printer.printLabel(pixels, paper, copies: copies),
            throwsA(isA<MarklifeException>()),
          );
        }
        await expectLater(
          printer.printLabel(
            pixels,
            LabelPrinterModel.marklifeP12.defaultPaper,
          ),
          throwsA(isA<MarklifeException>()),
        );
        await expectLater(
          printer.printLabel(Uint8List(2), paper),
          throwsA(isA<MarklifeException>()),
        );
        await expectLater(
          printer.printLabel(Uint8List(pixels.length)..[0] = 2, paper),
          throwsA(isA<MarklifeException>()),
        );
        expect(platform.chunks, isEmpty);
        expect(printer.connected, isTrue);
        await printer.printLabel(pixels, paper, copies: 2);
        final job = profile.job(pixels, paper.lengthMm, MarklifePaper.gap);
        expect(platform.received, [...job, ...job]);
        await printer.forget();
        expect(await store.load(), isNull);
      },
    );
  }
}
