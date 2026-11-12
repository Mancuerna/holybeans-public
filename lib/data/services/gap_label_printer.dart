import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/marklife_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/gap_printer_protocol.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/marklife_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

class GapLabelPrinter extends BleLink<int> implements LabelPrinter {
  GapLabelPrinter(
    this.profile, {
    this.store,
    this.ficheroResultTimeout = const Duration(seconds: 60),
  });
  final Duration ficheroResultTimeout;
  final GapPrinterModel profile;
  final PairedDeviceFile? store;
  @override
  LabelPrinterModel get model => profile == GapPrinterModel.p15
      ? LabelPrinterModel.pristarP15
      : LabelPrinterModel.fichero5836;
  MarklifeSession? _session;
  StreamSubscription<Uint8List>? _control;
  bool _disposed = false;
  @override
  bool printing = false;
  final _lines = <String>[];
  final _clock = Stopwatch()..start();
  _GapGatt _gatt = _GapGatt.credits;
  bool _withoutResponse = true;

  @override
  String get diagnosticReport =>
      'HolyBeans / ${model.displayName} / experimental\n'
      '14 mm gap labels; 96 dots; protocol=${profile == GapPrinterModel.p15 ? "L11" : "AiYin D11s"}\n'
      '${_lines.join("\n")}';

  @override
  void traceEvent(String event, Map<String, Object?> data) {
    final safe = switch (event) {
      'status' => {'previous': data['previous'], 'next': data['next']},
      'adapter' => {'state': data['state']},
      'gap.gatt' ||
      'gap.selected' ||
      'gap.failure' ||
      'marklife.mtu' ||
      'marklife.deviceMtu' ||
      'marklife.credits' ||
      'marklife.controlUnknown' ||
      'marklife.printerStatus' ||
      'marklife.response' ||
      'marklife.job' ||
      'marklife.sent' ||
      'marklife.accepted' ||
      'gap.awaitingResult' => data,
      'connect.error' ||
      'permissions.error' ||
      'adapter.error' ||
      'scan.error' ||
      'notification.error' ||
      'disconnect.error' ||
      'gap.mtuError' => {'failed': true},
      'permissions.request' ||
      'permissions.granted' ||
      'scan.start' ||
      'scan.stop' ||
      'connect.start' ||
      'connect.linked' ||
      'subscribe.start' ||
      'subscribe.ok' ||
      'connection.close' => <String, Object?>{},
      _ => null,
    };
    if (safe == null) return;
    _lines.add('${_clock.elapsedMilliseconds}ms $event ${jsonEncode(safe)}');
    if (_lines.length > 240) _lines.removeAt(0);
    if (event == 'marklife.sent' && profile == GapPrinterModel.fichero) {
      traceEvent('gap.awaitingResult', {
        'timeoutMs': ficheroResultTimeout.inMilliseconds,
      });
    }
  }

  @override
  String get service => _gatt.service;
  @override
  String get characteristic => _gatt.rx;
  @override
  bool matchesName(String? name) => profile.matchesName(name);

  @override
  void configureServices(FoundDevice device, List<BleService> services) {
    for (final s in services.take(16)) {
      traceEvent('gap.gatt', {
        'service': s.uuid,
        'characteristics': [
          for (final c in s.characteristics.take(16))
            {
              'uuid': c.uuid,
              'properties': c.properties.map((p) => p.name).toList(),
            },
        ],
      });
    }
    if (!matchesName(device.name)) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
    BleCharacteristic? find(_GapGatt candidate, String uuid) {
      for (final s in services) {
        if (s.uuid.toLowerCase() != candidate.service) continue;
        for (final c in s.characteristics) {
          if (c.uuid.toLowerCase() == uuid) return c;
        }
      }
      return null;
    }

    // Resolve a known serial interface before any write. Never change transport
    // after a print has started or retry a job on another characteristic.
    for (final candidate in _GapGatt.values) {
      final rx = find(candidate, candidate.rx);
      final tx = find(candidate, candidate.tx);
      final control = candidate.control == null
          ? null
          : find(candidate, candidate.control!);
      if (rx == null ||
          !rx.properties.contains(CharacteristicProperty.notify) ||
          tx == null) {
        continue;
      }
      final noResponse = tx.properties.contains(
        CharacteristicProperty.writeWithoutResponse,
      );
      final response = tx.properties.contains(CharacteristicProperty.write);
      if (!noResponse && !response) continue;
      if (candidate.control != null &&
          (control == null ||
              !control.properties.contains(CharacteristicProperty.notify))) {
        continue;
      }
      _gatt = candidate;
      // Credit-based ff00 matches the tested P12 path; plain UARTs use
      // acknowledged writes when offered, 20-byte chunks and pacing otherwise.
      _withoutResponse = candidate.control != null || !response;
      if (_withoutResponse && !noResponse) continue;
      traceEvent('gap.selected', {
        'profile': candidate.name,
        'credits': candidate.control != null,
        'withoutResponse': _withoutResponse,
      });
      return;
    }
    throw const MarklifeException(MarklifeFailure.unsupported);
  }

  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    final gatt = _gatt;
    late final MarklifeSession session;
    session = MarklifeSession(
      encodeJob: profile.job,
      requiresCredits: gatt.control != null,
      resultTimeout: profile == GapPrinterModel.fichero
          ? ficheroResultTimeout
          : const Duration(seconds: 15),
      responseFailure: profile == GapPrinterModel.fichero
          ? GapPrinterModel.ficheroError
          : null,
      acknowledgement: profile == GapPrinterModel.fichero
          ? GapPrinterModel.ficheroAck
          : null,
      trace: traceEvent,
      write: (bytes) async {
        if (_disposed || !identical(_session, session)) {
          throw const MarklifeException(MarklifeFailure.disconnected);
        }
        await UniversalBle.write(
          deviceId,
          gatt.service,
          gatt.tx,
          bytes,
          withoutResponse: _withoutResponse,
          timeout: const Duration(seconds: 3),
        );
      },
    );
    _session = session;
    if (gatt.control case final control?) {
      _control = UniversalBle.characteristicValueStream(deviceId, control)
          .listen(
            session.receiveControl,
            onError: (Object error) {
              traceEvent('notification.error', {});
              session.close();
            },
          );
      await UniversalBle.subscribeNotifications(
        deviceId,
        gatt.service,
        control,
      );
    }
    if (_disposed || !identical(_session, session)) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
    try {
      final mtu = await UniversalBle.requestMtu(
        deviceId,
        247,
        timeout: const Duration(seconds: 3),
      );
      // Plain UART connections retain conservative 20-byte payloads regardless of MTU.
      session.setMtu(gatt.control == null ? 23 : mtu);
    } on Object {
      traceEvent('gap.mtuError', {});
      session.setMtu(23);
    }
    if (_disposed || !identical(_session, session)) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
  }

  @override
  int? parse(Uint8List packet) {
    _session?.receive(packet);
    return null;
  }

  @override
  void connectionClosed() {
    _session?.close();
    _session = null;
    _control?.cancel();
    _control = null;
  }

  @override
  Future<void> printLabel(
    Uint8List pixels,
    LabelPaper paper, {
    int copies = 1,
  }) async {
    if (!model.papers.contains(paper) || copies < 1 || copies > 10) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
    final lengthMm = paper.lengthMm;
    if (printing) throw const MarklifeException(MarklifeFailure.busy);
    final session = _session;
    if (!connected || session == null) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
    // Validate before starting a job or tearing down a usable connection.
    profile.job(pixels, lengthMm, MarklifePaper.gap);
    printing = true;
    notifyListeners();
    try {
      for (var copy = 0; copy < copies; copy++) {
        await session.print(pixels, lengthMm, MarklifePaper.gap);
      }
      // A completed write is not an ACK. The session waits for the printer;
      // after acceptance the connection remains available for a manual job.
    } on Object catch (error) {
      traceEvent('gap.failure', {
        'reason': error is MarklifeException ? error.failure.name : 'transport',
      });
      await disconnect();
      rethrow;
    } finally {
      printing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<FoundDevice?> loadRemembered() async {
    final device = await store?.load();
    return matchesName(device?.name) ? device : null;
  }

  @override
  Future<void> saveRemembered(FoundDevice? device) async {
    await store?.save(device);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// UART UUIDs documented by atctwo for L13 and thermal-label for Marklife.
enum _GapGatt {
  credits(
    MarklifeProtocol.service,
    MarklifeProtocol.rx,
    MarklifeProtocol.tx,
    MarklifeProtocol.control,
  ),
  uart(
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '49535343-1e4d-4bd9-ba61-23c647249616',
    '49535343-8841-43f4-a8d4-ecbe34729bb3',
  ),
  printer(
    '000018f0-0000-1000-8000-00805f9b34fb',
    '00002af0-0000-1000-8000-00805f9b34fb',
    '00002af1-0000-1000-8000-00805f9b34fb',
  ),
  serial(
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
    'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
  );

  const _GapGatt(this.service, this.rx, this.tx, [this.control]);
  final String service;
  final String rx;
  final String tx;
  final String? control;
}
