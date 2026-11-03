import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';

/// A pressure sensor the test drives: [emit] sends a reading in bar and a
/// search finds [nearby]. Like the real one, it accepts no commands.
class FakePressureSensor extends ChangeNotifier implements PressureSensor {
  FakePressureSensor({
    this.name,
    bool connected = false,
    this.nearby = const [],
  }) : status = connected ? DeviceStatus.connected : DeviceStatus.idle;

  final List<FoundDevice> nearby;
  // Synchronous, so a reading lands at the time the test set.
  final _readings = StreamController<double>.broadcast(sync: true);

  @override
  String? name;
  @override
  DeviceStatus status;
  @override
  double? bar;
  @override
  List<FoundDevice> found = const [];
  @override
  bool hasSearched = false;

  @override
  bool get connected => status == DeviceStatus.connected;
  @override
  Stream<double> get readings => _readings.stream;

  void emit(double value) {
    bar = value;
    _readings.add(value);
    notifyListeners();
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
  Future<void> pair(FoundDevice sensor) async {
    name = sensor.name;
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
    bar = null;
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
    _readings.close();
    super.dispose();
  }
}
