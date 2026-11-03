import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';

/// A scale the test drives: [emit] sends a reading, [commands] keeps what
/// the app asked for and a search finds [nearby].
class FakeScale extends ChangeNotifier implements Scale {
  FakeScale({this.name, bool connected = false, this.nearby = const []})
    : status = connected ? DeviceStatus.connected : DeviceStatus.idle;

  final List<FoundDevice> nearby;

  /// Disconnected by the user: automatic attempts leave it alone, as the
  /// real link does.
  bool heldOff = false;

  /// The scale went away by itself (switched off, out of range).
  void lose() {
    status = DeviceStatus.idle;
    reading = null;
    notifyListeners();
  }

  @override
  List<FoundDevice> get rememberedScales =>
      name == null ? [] : [FoundDevice(id: name!, name: name!)];
  @override
  String? get activeScaleId => connected ? name : null;
  @override
  Future<void> forgetScale(String id) => forget();

  final commands = <ScaleCommand>[];
  // Synchronous, so a reading lands at the time the test set.
  final _readings = StreamController<ScaleReading>.broadcast(sync: true);
  final _doses = StreamController<double>.broadcast(sync: true);

  @override
  Stream<double> get doses => _doses.stream;

  void emitDose(double grams) => _doses.add(grams);

  @override
  String? name;
  @override
  DeviceStatus status;
  @override
  ScaleReading? reading;
  @override
  List<FoundDevice> found = const [];
  @override
  bool hasSearched = false;

  @override
  bool get connected => status == DeviceStatus.connected;
  @override
  Stream<ScaleReading> get readings => _readings.stream;

  void emit(
    double grams, {
    int battery = 77,
    double flow = 0,
    int timerMs = 0,
    bool? timerRunning,
  }) {
    reading = ScaleReading(
      grams: grams,
      batteryPercent: battery,
      flowGramsPerSecond: flow,
      timerMs: timerMs,
      timerRunning: timerRunning,
    );
    _readings.add(reading!);
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
  Future<void> pair(FoundDevice scale) async {
    name = scale.name;
    found = const [];
    hasSearched = false;
    status = DeviceStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> connect({bool automatic = false}) async {
    if (name == null || (automatic && heldOff)) return;
    heldOff = false;
    status = DeviceStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    heldOff = true;
    status = DeviceStatus.idle;
    reading = null;
    notifyListeners();
  }

  @override
  Future<void> forget() async {
    await disconnect();
    name = null;
    notifyListeners();
  }

  @override
  Future<bool> send(ScaleCommand command) async {
    if (!connected) return false;
    commands.add(command);
    return true;
  }

  @override
  void dispose() {
    _doses.close();
    _readings.close();
    super.dispose();
  }
}
