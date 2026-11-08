import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/marklife_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/marklife_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

class MarklifePrinter extends BleLink<int> implements LabelPrinter {
  MarklifePrinter([this.store]);
  // A missing store gives diagnostic callers a connection without persistence.
  final PairedDeviceFile? store;
  @override
  LabelPrinterModel get model => LabelPrinterModel.marklifeP12;
  MarklifeSession? _session;
  StreamSubscription<Uint8List>? _control;
  bool _disposed = false;
  @override
  bool printing = false;
  final _lines = <String>[];
  final _clock = Stopwatch()..start();

  @override
  String get diagnosticReport =>
      'HolyBeans / Pristar-Marklife P12 / experimental\n'
      '96 dots; 203 dpi; L11; GATT ff00; continuous tape 15 mm\n'
      '${_lines.join('\n')}';

  @override
  void traceEvent(String event, Map<String, Object?> data) {
    // Explicit allowlist: no names, addresses, label text, raster or raw replies.
    final safe = switch (event) {
      'status' => {'previous': data['previous'], 'next': data['next']},
      'adapter' => {'state': data['state']},
      'gatt.services' => {'discovered': true},
      'gatt.selected' => {'profile': 'ff00/ff01/ff02/ff03'},
      'marklife.gatt' => data,
      'marklife.mtu' ||
      'marklife.deviceMtu' ||
      'marklife.credits' ||
      'marklife.controlUnknown' ||
      'marklife.printerStatus' ||
      'marklife.response' ||
      'marklife.job' ||
      'marklife.sent' ||
      'marklife.accepted' ||
      'marklife.failure' => data,
      'connect.error' ||
      'permissions.error' ||
      'adapter.error' ||
      'scan.error' ||
      'notification.error' ||
      'disconnect.error' ||
      'marklife.mtuError' => {'failed': true},
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
    if (safe != null) {
      _lines.add('${_clock.elapsedMilliseconds}ms $event ${jsonEncode(safe)}');
      if (_lines.length > 200) _lines.removeAt(0);
    }
  }

  @override
  String get service => MarklifeProtocol.service;
  @override
  String get characteristic => MarklifeProtocol.rx;
  @override
  bool matchesName(String? name) => MarklifeProtocol.matchesName(name);

  @override
  void configureServices(FoundDevice device, List<BleService> services) {
    bool has(String uuid, CharacteristicProperty property) => services.any(
      (s) =>
          s.uuid.toLowerCase() == service &&
          s.characteristics.any(
            (c) =>
                c.uuid.toLowerCase() == uuid && c.properties.contains(property),
          ),
    );
    final rx = has(characteristic, CharacteristicProperty.notify);
    final tx = has(
      MarklifeProtocol.tx,
      CharacteristicProperty.writeWithoutResponse,
    );
    final cx = has(MarklifeProtocol.control, CharacteristicProperty.notify);
    traceEvent('marklife.gatt', {'rx': rx, 'tx': tx, 'control': cx});
    if (!matchesName(device.name) || !rx || !tx || !cx) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
  }

  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    late final MarklifeSession session;
    session = MarklifeSession(
      write: (bytes) async {
        if (_disposed || !identical(_session, session)) {
          throw const MarklifeException(MarklifeFailure.disconnected);
        }
        await UniversalBle.write(
          deviceId,
          service,
          MarklifeProtocol.tx,
          bytes,
          withoutResponse: true,
          timeout: const Duration(seconds: 3),
        );
      },
      trace: traceEvent,
    );
    _session = session;
    _control =
        UniversalBle.characteristicValueStream(
          deviceId,
          MarklifeProtocol.control,
        ).listen(
          session.receiveControl,
          onError: (Object error) {
            traceEvent('notification.error', {});
            session.close();
          },
        );
    await UniversalBle.subscribeNotifications(
      deviceId,
      service,
      MarklifeProtocol.control,
    );
    if (_disposed || !identical(_session, session)) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
    try {
      final mtu = await UniversalBle.requestMtu(
        deviceId,
        247,
        timeout: const Duration(seconds: 3),
      );
      session.setMtu(mtu);
    } on Object {
      traceEvent('marklife.mtuError', {});
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
    if (!model.papers.contains(paper) ||
        copies < 1 ||
        copies > 10 ||
        pixels.length != paper.printableWidth * paper.printableHeight ||
        pixels.any((pixel) => pixel > 1)) {
      throw const MarklifeException(MarklifeFailure.unsupported);
    }
    if (printing) throw const MarklifeException(MarklifeFailure.busy);
    final session = _session;
    if (!connected || session == null) {
      throw const MarklifeException(MarklifeFailure.disconnected);
    }
    printing = true;
    notifyListeners();
    try {
      for (var copy = 0; copy < copies; copy++) {
        await session.print(pixels, paper.lengthMm, MarklifePaper.continuous);
      }
    } on Object catch (error) {
      traceEvent('marklife.failure', {
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
