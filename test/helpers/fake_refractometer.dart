import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/refractometer.dart';

/// A refractometer the test drives: [emit] sends what the device reports
/// and [measures] counts the times the app asked it to measure.
class FakeRefractometer extends ChangeNotifier implements Refractometer {
  FakeRefractometer({this.name, bool connected = false, this.nearby = const []})
    : status = connected ? DeviceStatus.connected : DeviceStatus.idle;

  final List<FoundDevice> nearby;
  // Synchronous, so a message lands when the test sends it.
  final _messages = StreamController<R2Message>.broadcast(sync: true);
  int measures = 0;

  @override
  String? name;
  @override
  DeviceStatus status;
  @override
  double? tdsPercent;
  @override
  bool measuring = false;
  @override
  List<FoundDevice> found = const [];
  @override
  bool hasSearched = false;

  @override
  bool get connected => status == DeviceStatus.connected;
  @override
  Stream<R2Message> get messages => _messages.stream;

  void emit(R2Message message) {
    measuring = message is R2Measuring;
    if (message case R2Result(:final tdsPercent)) {
      this.tdsPercent = tdsPercent;
    }
    _messages.add(message);
    notifyListeners();
  }

  @override
  Future<bool> measure() async {
    if (!connected) return false;
    measures++;
    emit(const R2Measuring());
    return true;
  }

  @override
  Future<void> search() async {
    hasSearched = true;
    found = nearby;
    notifyListeners();
  }

  @override
  Future<void> stopSearch() async {}

  @override
  Future<void> pair(FoundDevice device) async {
    name = device.name;
    status = DeviceStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> connect({bool automatic = false}) async {
    if (name == null) return;
    status = DeviceStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    status = DeviceStatus.idle;
    notifyListeners();
  }

  @override
  Future<void> forget() async {
    await disconnect();
    name = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _messages.close();
    super.dispose();
  }
}
