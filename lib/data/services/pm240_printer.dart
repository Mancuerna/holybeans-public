import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/domain/pm240_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

class Pm240Printer extends BleLink<int> implements LabelPrinter {
  Pm240Printer({
    this.store,
    this.responseTimeout = const Duration(seconds: 5),
    this.chunkDelay = const Duration(milliseconds: 30),
    this.observationTime = const Duration(seconds: 3),
  });
  final PairedDeviceFile? store;
  final Duration responseTimeout;
  final Duration chunkDelay;
  final Duration observationTime;
  StreamSubscription<Uint8List>? _control;
  Completer<int?>? _pending;
  int _generation = 0;
  bool _disposed = false;
  Pm240Failure? _failure;
  final _lines = <String>[];
  final _clock = Stopwatch()..start();

  @override
  LabelPrinterModel get model => LabelPrinterModel.typonosPm240;
  @override
  bool printing = false;
  @override
  String get service => Pm240Protocol.service;
  @override
  String get characteristic => Pm240Protocol.responses.first;
  @override
  bool matchesName(String? name) => model.matchesName(name);
  @override
  String get diagnosticReport =>
      'HolyBeans / Typonos PM240 / TSPL\n'
      '50 x 30 mm; 203 dpi; raster 384 x 224; gap preserved\n'
      '${_lines.join('\n')}';

  @override
  void traceEvent(String event, Map<String, Object?> data) {
    // Exclude names, addresses, label contents and raw CONFIG/RFID responses.
    final safe = switch (event) {
      'status' => {'previous': data['previous'], 'next': data['next']},
      'scan.stop' => {'supportedDevices': data['supportedDevices']},
      'pm240.rx' || 'pm240.job' || 'pm240.failure' => data,
      'permissions.request' ||
      'permissions.granted' ||
      'scan.start' ||
      'connect.start' ||
      'connect.linked' ||
      'subscribe.ok' ||
      'connection.close' ||
      'pm240.sentUnconfirmed' ||
      'pm240.statusQuery' => <String, Object?>{},
      'connect.error' ||
      'scan.error' ||
      'notification.error' ||
      'disconnect.error' => {'failed': true},
      _ => null,
    };
    if (safe == null) return;
    _lines.add('${_clock.elapsedMilliseconds}ms $event ${jsonEncode(safe)}');
    if (_lines.length > 240) _lines.removeAt(0);
  }

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
    if (!matchesName(device.name) ||
        !has(Pm240Protocol.tx, CharacteristicProperty.writeWithoutResponse) ||
        !Pm240Protocol.responses.every(
          (c) => has(c, CharacteristicProperty.notify),
        )) {
      throw const Pm240Exception(Pm240Failure.unsupported);
    }
  }

  @override
  Future<void> onNotificationsSubscribed(String deviceId) async {
    final generation = _generation;
    _failure = null;
    final control = Pm240Protocol.responses.last;
    _control = UniversalBle.characteristicValueStream(deviceId, control).listen(
      (bytes) {
        if (generation == _generation) parse(bytes);
      },
      onError: (Object error) {
        _failure = Pm240Failure.disconnected;
        if (_pending?.isCompleted == false) _pending!.complete(null);
      },
    );
    await UniversalBle.subscribeNotifications(deviceId, service, control);
    _check(generation);
    await _queryStatus(deviceId, generation);
  }

  void _check(int generation) {
    if (_disposed || generation != _generation || connectionTargetId == null) {
      throw const Pm240Exception(Pm240Failure.disconnected);
    }
    if (_failure case final failure?) throw Pm240Exception(failure);
  }

  @override
  int? parse(Uint8List bytes) {
    traceEvent('pm240.rx', {
      'bytes': bytes.length,
      if (bytes.length == 1) 'status': bytes.single,
    });
    if (bytes.length == 1) {
      if (bytes.single != 0) _failure = Pm240Failure.printer;
      if (_pending?.isCompleted == false) _pending!.complete(bytes.single);
    }
    return null;
  }

  Future<void> _write(String id, Uint8List bytes, int generation) async {
    _check(generation);
    await UniversalBle.write(
      id,
      service,
      Pm240Protocol.tx,
      bytes,
      withoutResponse: true,
      timeout: const Duration(seconds: 5),
    );
    _check(generation);
  }

  Future<void> _queryStatus(String id, int generation) async {
    final pending = _pending = Completer<int?>();
    try {
      traceEvent('pm240.statusQuery', {});
      await _write(id, Pm240Protocol.statusQuery, generation);
      final response = await pending.future.timeout(
        responseTimeout,
        onTimeout: () => null,
      );
      _check(generation);
      if (response == null) throw const Pm240Exception(Pm240Failure.noStatus);
      if (response != 0) throw const Pm240Exception(Pm240Failure.printer);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  @override
  Future<void> printLabel(
    Uint8List pixels,
    LabelPaper paper, {
    int copies = 1,
  }) async {
    if (!model.papers.contains(paper) || copies < 1 || copies > 10) {
      throw const Pm240Exception(Pm240Failure.unsupported);
    }
    final job = Pm240Protocol.job(pixels);
    if (printing) throw const Pm240Exception(Pm240Failure.busy);
    final id = connectedId;
    if (id == null) throw const Pm240Exception(Pm240Failure.disconnected);
    final generation = _generation;
    printing = true;
    notifyListeners();
    try {
      for (var copy = 0; copy < copies; copy++) {
        await _queryStatus(id, generation);
        traceEvent('pm240.job', {
          'bytes': job.length,
          'copy': copy + 1,
          'copies': copies,
        });
        for (var offset = 0; offset < job.length; offset += 20) {
          final end = (offset + 20).clamp(0, job.length);
          await _write(id, Uint8List.sublistView(job, offset, end), generation);
          await Future<void>.delayed(chunkDelay);
        }
        traceEvent('pm240.sentUnconfirmed', {});
        await Future<void>.delayed(observationTime);
        _check(generation);
        // Status is readiness, not a paper-output acknowledgement. Check again
        // before completing or sending the next explicitly requested copy.
        await _queryStatus(id, generation);
      }
    } on Object catch (error) {
      traceEvent('pm240.failure', {
        'reason': error is Pm240Exception ? error.failure.name : 'transport',
      });
      await disconnect();
      rethrow;
    } finally {
      printing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void connectionClosed() {
    _generation++;
    _failure = Pm240Failure.disconnected;
    if (_pending?.isCompleted == false) _pending!.complete(null);
    _control?.cancel();
    _control = null;
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
