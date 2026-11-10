import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/ble_link.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/difluid_r2_protocol.dart';
import 'package:universal_ble/universal_ble.dart';

export 'package:holybeans/data/services/paired_device.dart';
export 'package:holybeans/domain/difluid_r2_protocol.dart'
    show R2Failed, R2Measuring, R2Message, R2Result, R2TestCount;

/// A Bluetooth refractometer as the app sees it: it reports what it
/// measures, whether asked from the app or with its own button, and can be
/// asked to measure. Nothing else is ever sent (no settings, no
/// calibration).
abstract interface class Refractometer implements PairedDevice {
  /// The last TDS measured while connected, in percent.
  double? get tdsPercent;

  /// Whether a measurement is under way.
  bool get measuring;

  /// Measurements starting, results and failures as they arrive.
  Stream<R2Message> get messages;

  /// Asks it to measure the sample as its own button does; false when it
  /// could not be asked.
  Future<bool> measure();
}

/// A DiFluid R2 over Bluetooth Low Energy.
class BleRefractometer extends BleLink<R2Message> implements Refractometer {
  BleRefractometer(this.store) {
    _messages = readings.listen(_follow);
  }

  /// Opens the file that remembers the refractometer on this phone.
  static Future<PairedDeviceFile> openStore() =>
      PairedDeviceFile.open('refractometer.json');

  /// An average of several tests takes a while; one that never reports
  /// back stops counting as under way after this.
  static const _measureTimeout = Duration(seconds: 60);

  /// How long to wait for the number of tests before measuring once.
  static const _countTimeout = Duration(seconds: 2);

  final PairedDeviceFile store;
  late final StreamSubscription<R2Message> _messages;
  double? _tds;
  bool _measuring = false;
  Timer? _giveUp;
  Completer<int?>? _count;
  int _measurementGeneration = 0;

  @override
  void connectionClosed() {
    _measurementGeneration++;
    _giveUp?.cancel();
    _measuring = false;
    _count?.complete(null);
    _count = null;
  }

  @override
  String get service => DifluidR2Uuids.service;

  @override
  String get characteristic => DifluidR2Uuids.characteristic;

  @override
  bool matchesName(String? name) => isDifluidR2Name(name);

  @override
  R2Message? parse(Uint8List packet) => parseR2Message(packet);

  @override
  Future<FoundDevice?> loadRemembered() => store.load();

  @override
  Future<void> saveRemembered(FoundDevice? device) => store.save(device);

  @override
  double? get tdsPercent => connected ? _tds : null;

  @override
  bool get measuring => connected && _measuring;

  @override
  Stream<R2Message> get messages => readings;

  void _follow(R2Message message) {
    switch (message) {
      case R2Measuring():
        _setMeasuring(true);
      case R2Result(:final tdsPercent):
        _tds = tdsPercent;
        _setMeasuring(false);
      case R2Failed():
        _setMeasuring(false);
      case R2TestCount(:final count):
        _count?.complete(count);
        _count = null;
    }
  }

  void _setMeasuring(bool value) {
    _giveUp?.cancel();
    _measuring = value;
    if (value) {
      _giveUp = Timer(_measureTimeout, () => _setMeasuring(false));
    }
    notifyListeners();
  }

  Future<void> _write(String id, List<int> frame) => UniversalBle.write(
    id,
    DifluidR2Uuids.service,
    DifluidR2Uuids.characteristic,
    Uint8List.fromList(frame),
  );

  /// The number of tests the R2 averages with its own button, read every
  /// time in case it was changed on the device; null without an answer.
  Future<int?> _testCount(String id) async {
    final answer = _count = Completer<int?>();
    try {
      await _write(id, difluidGetNumberOfTests);
      return await answer.future.timeout(_countTimeout);
    } on Object {
      return null;
    } finally {
      if (identical(_count, answer)) _count = null;
    }
  }

  @override
  Future<bool> measure() async {
    final id = connectedId;
    if (id == null || _measuring) return false;
    final generation = _measurementGeneration;
    _setMeasuring(true);
    final count = await _testCount(id);
    if (generation != _measurementGeneration || connectedId != id) return false;
    try {
      // The average takes the count and stores it: passing the one it has
      // leaves the setting as it was.
      await _write(
        id,
        count == null || count <= 1
            ? difluidSingleTest
            : difluidAverageTest(count),
      );
    } on Object {
      if (generation == _measurementGeneration) _setMeasuring(false);
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _messages.cancel();
    super.dispose();
  }
}
