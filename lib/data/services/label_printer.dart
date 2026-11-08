import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/ble_trace.dart';
import 'package:holybeans/data/services/niimbot_connection_log.dart';
import 'package:holybeans/data/services/niimbot_session.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/niimbot_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

abstract interface class LabelPrinter implements PairedDevice {
  LabelPrinterModel get model;
  bool get printing;
  String get diagnosticReport;
  Future<void> printLabel(Uint8List pixels, LabelPaper paper, {int copies = 1});
  void dispose();
}

class NiimbotLabelPrinter extends BleLink<NiimbotPacket>
    implements LabelPrinter {
  NiimbotLabelPrinter(this.store, {required this.model, super.trace})
    : _diagnostics = NiimbotConnectionLog(model) {
    if (!model.isNiimbot) throw ArgumentError.value(model, 'model');
  }
  final NiimbotConnectionLog _diagnostics;
  @override
  String get diagnosticReport => _diagnostics.report;
  @override
  void traceEvent(String event, Map<String, Object?> data) {
    emitBleTrace(_diagnostics.record, event, data);
    super.traceEvent(event, data);
  }

  final PairedDeviceFile store;
  @override
  final LabelPrinterModel model;
  NiimbotSession? _session;
  bool _disposed = false;
  @override
  bool printing = false;

  @override
  String get service => 'e7810a71-73ae-499d-8c15-faa9aef0c3f2';
  @override
  String get characteristic => 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f';
  @override
  bool matchesName(String? name) => model.matchesName(name);

  @override
  void configureServices(FoundDevice device, List<BleService> services) {
    if (!matchesName(device.name) ||
        !services.any(
          (s) =>
              s.uuid.toLowerCase() == service &&
              s.characteristics.any(
                (c) => c.uuid.toLowerCase() == characteristic,
              ),
        )) {
      throw const LabelPrintException(LabelPrintFailure.unsupported);
    }
  }

  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    late final NiimbotSession session;
    var payloadBytes = 20;
    session = NiimbotSession(
      model: model,
      responseTimeout: Duration(
        seconds: model == LabelPrinterModel.d11H ? 10 : 5,
      ),
      trace: traceEvent,
      rowBatchBytes: () => payloadBytes,
      write: (bytes) async {
        // D11-H uses the negotiated payload; other profiles retain 20 bytes.
        for (var offset = 0; offset < bytes.length; offset += payloadBytes) {
          if (_disposed || !identical(_session, session)) {
            throw const LabelPrintException(LabelPrintFailure.disconnected);
          }
          final end = (offset + payloadBytes).clamp(0, bytes.length);
          await UniversalBle.write(
            deviceId,
            service,
            characteristic,
            Uint8List.sublistView(bytes, offset, end),
            withoutResponse: true,
            timeout: const Duration(seconds: 3),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      },
    );
    _session = session;
    // B5 can occupy 23 bytes, exceeding the default 20-byte ATT payload.
    // Ask Android for a larger receive MTU; keep writes and decoding compatible
    // with the minimum if negotiation is refused. This is connection-local.
    if ((model == LabelPrinterModel.b1Pro || model == LabelPrinterModel.d11H) &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      traceEvent('niimbot.mtu.request', {'requested': 247});
      try {
        final mtu = await UniversalBle.requestMtu(
          deviceId,
          247,
          timeout: const Duration(seconds: 3),
        );
        traceEvent('niimbot.mtu.result', {'mtu': mtu});
        if (model == LabelPrinterModel.d11H) {
          payloadBytes = (mtu - 3).clamp(20, 240);
        }
      } on Object catch (error) {
        traceEvent('niimbot.mtu.error', {'error': '$error'});
      }
    }
    if (_disposed || !identical(_session, session)) {
      throw const LabelPrintException(LabelPrintFailure.disconnected);
    }
    await session.identify();
    final identity = session.identity!;
    traceEvent('niimbot.identified', {
      'model': model.label,
      'id': identity.id,
      'family': identity.family.name,
      'protocolVersion': identity.protocolVersion,
    });
  }

  @override
  NiimbotPacket? parse(Uint8List packet) {
    _session?.receive(packet);
    return null;
  }

  @override
  void connectionClosed() {
    _session?.close();
    _session = null;
  }

  @override
  Future<void> printLabel(
    Uint8List pixels,
    LabelPaper paper, {
    int copies = 1,
  }) async {
    if (!model.papers.contains(paper) ||
        pixels.length != paper.printableWidth * paper.printableHeight) {
      throw const LabelPrintException(LabelPrintFailure.unsupported);
    }
    if (printing) throw const LabelPrintException(LabelPrintFailure.busy);
    final session = _session;
    if (!connected || session == null) {
      throw const LabelPrintException(LabelPrintFailure.disconnected);
    }
    printing = true;
    notifyListeners();
    try {
      await session.print(pixels, paper.printableWidth, copies: copies);
    } on Object {
      await disconnect();
      rethrow;
    } finally {
      printing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  Future<FoundDevice?> loadRemembered() async {
    final device = await store.load();
    return matchesName(device?.name) ? device : null;
  }

  @override
  Future<void> saveRemembered(FoundDevice? device) => store.save(device);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class D110LabelPrinter extends NiimbotLabelPrinter {
  D110LabelPrinter(super.store, {super.trace})
    : super(model: LabelPrinterModel.d110);
}
