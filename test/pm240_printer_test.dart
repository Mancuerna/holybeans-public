import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pm240_printer.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/pm240_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_pm240_ble_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = FoundDevice(id: 'private-address', name: 'PM240_private-name');
  final paper = LabelPrinterModel.typonosPm240.defaultPaper;
  final pixels = Uint8List(384 * 224);
  late PmPrintPlatform platform;
  late Pm240Printer printer;
  late Directory directory;
  late PairedDeviceFile store;
  setUp(() async {
    platform = PmPrintPlatform();
    UniversalBle.setInstance(platform);
    directory = await Directory.systemTemp.createTemp('pm240-test-');
    store = PairedDeviceFile(File(path.join(directory.path, 'paired.json')));
    printer = Pm240Printer(
      store: store,
      responseTimeout: const Duration(milliseconds: 30),
      chunkDelay: Duration.zero,
      observationTime: Duration.zero,
    );
  });
  tearDown(() async {
    await printer.disconnect();
    printer.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'scan filters lookalikes and pairing remembers without printing',
    () async {
      await printer.search();
      await Future<void>.delayed(Duration.zero);
      await printer.stopSearch();
      expect(printer.found.map((d) => d.name), ['PM240_TEST']);
      await printer.pair(device);
      expect(printer.connected, isTrue);
      expect(platform.chunks, [Pm240Protocol.statusQuery]);
      expect(
        platform.events.where((e) => e.startsWith('subscribe:')),
        hasLength(2),
      );
      final reopened = Pm240Printer(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.name, device.name);
      await printer.forget();
      expect(await store.load(), isNull);
      expect(printer.diagnosticReport, isNot(contains('private-')));
    },
  );

  test(
    'manual jobs and requested copies retain exact tested TSPL bytes',
    () async {
      await printer.pair(device);
      await printer.printLabel(pixels, paper, copies: 2);
      expect(platform.queries, 5);
      final rasterChunks = platform.chunks.where(
        (c) => !listEquals(c, Pm240Protocol.statusQuery),
      );
      expect(rasterChunks.expand((c) => c), [
        ...Pm240Protocol.job(pixels),
        ...Pm240Protocol.job(pixels),
      ]);
      expect(printer.connected, isTrue);
      expect(printer.printing, isFalse);
      expect(printer.diagnosticReport, contains('pm240.sentUnconfirmed'));
      // Another manual job is allowed after the previous job finishes.
      await printer.printLabel(pixels, paper);
      expect(platform.queries, 7);
    },
  );

  test('unknown name and missing GATT characteristic never write', () async {
    await printer.pair(const FoundDevice(id: 'other', name: 'PM240C'));
    expect(printer.status, DeviceStatus.failed);
    expect(platform.chunks, isEmpty);
    platform.hasControl = false;
    await printer.pair(device);
    expect(printer.status, DeviceStatus.failed);
    expect(platform.chunks, isEmpty);
  });

  for (final reply in <List<int>?>[
    null,
    [4],
    ascii.encode('CONFIG private-serial'),
  ]) {
    test(
      'missing, error or multibyte status prevents printing: $reply',
      () async {
        platform.reply = reply;
        await printer.pair(device);
        expect(printer.status, DeviceStatus.failed);
        await expectLater(
          printer.printLabel(pixels, paper),
          throwsA(isA<Pm240Exception>()),
        );
        expect(platform.chunks, [Pm240Protocol.statusQuery]);
        expect(printer.diagnosticReport, isNot(contains('private-')));
      },
    );
  }

  test(
    'invalid paper, bitmap and copies cannot write or break a connection',
    () async {
      await printer.pair(device);
      for (final copies in [0, 11]) {
        await expectLater(
          printer.printLabel(pixels, paper, copies: copies),
          throwsA(isA<Pm240Exception>()),
        );
      }
      await expectLater(
        printer.printLabel(pixels, LabelPaper.mm50x30),
        throwsA(isA<Pm240Exception>()),
      );
      await expectLater(
        printer.printLabel(Uint8List(2), paper),
        throwsArgumentError,
      );
      await expectLater(
        printer.printLabel(Uint8List(384 * 224)..[0] = 2, paper),
        throwsArgumentError,
      );
      expect(platform.chunks, [Pm240Protocol.statusQuery]);
      expect(printer.connected, isTrue);
    },
  );

  test('fresh status blocks printing after paper is removed', () async {
    await printer.pair(device);
    platform.reply = [4];
    await expectLater(
      printer.printLabel(pixels, paper),
      throwsA(isA<Pm240Exception>()),
    );
    expect(platform.chunks, [
      Pm240Protocol.statusQuery,
      Pm240Protocol.statusQuery,
    ]);
    expect(printer.connected, isFalse);
  });

  test('post-job error prevents the next requested copy', () async {
    await printer.pair(device);
    platform.failStatusAfterQuery = 2;
    await expectLater(
      printer.printLabel(pixels, paper, copies: 3),
      throwsA(isA<Pm240Exception>()),
    );
    expect(
      platform.chunks
          .where((c) => !listEquals(c, Pm240Protocol.statusQuery))
          .expand((c) => c),
      Pm240Protocol.job(pixels),
    );
    expect(printer.connected, isFalse);
    expect(platform.queries, 3);
  });

  test('write failure aborts all copies without replay', () async {
    await printer.pair(device);
    platform.failAtChunk = 4;
    await expectLater(
      printer.printLabel(pixels, paper, copies: 3),
      throwsStateError,
    );
    await expectLater(
      printer.printLabel(pixels, paper),
      throwsA(isA<Pm240Exception>()),
    );
    expect(platform.chunks, hasLength(4));
    expect(printer.connected, isFalse);
    expect(printer.diagnosticReport, isNot(contains('private-')));
  });

  test(
    'dispose during a late connection prevents subscriptions and writes',
    () async {
      platform.gate = Completer<void>();
      final opening = printer.pair(device);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      printer.dispose();
      platform.gate!.complete();
      await opening;
      expect(platform.chunks, isEmpty);
      expect(platform.events.last, 'disconnect');
      printer = Pm240Printer();
    },
  );

  for (final dispose in [false, true]) {
    test(
      'busy guard and cancellation during raster stops further writes (dispose=$dispose)',
      () async {
        await printer.pair(device);
        platform.writeGate = Completer<void>();
        final printing = printer.printLabel(pixels, paper, copies: 2);
        final failed = expectLater(printing, throwsA(isA<Pm240Exception>()));
        while (platform.chunks.length < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await expectLater(
          printer.printLabel(pixels, paper),
          throwsA(
            isA<Pm240Exception>().having(
              (e) => e.failure,
              'reason',
              Pm240Failure.busy,
            ),
          ),
        );
        if (dispose) {
          printer.dispose();
        } else {
          platform.updateConnection(device.id, false);
          await Future<void>.delayed(Duration.zero);
        }
        platform.writeGate!.complete();
        await failed;
        expect(platform.chunks, hasLength(3));
        if (dispose) {
          expect(platform.events.last, 'disconnect');
          printer = Pm240Printer();
        } else {
          expect(printer.connected, isFalse);
        }
      },
    );
  }
}
