import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/domain/label_printer_profile.dart';

class FakeLabelPrinter extends ChangeNotifier implements LabelPrinter {
  FakeLabelPrinter({this.model = LabelPrinterModel.d110});
  @override
  final LabelPrinterModel model;
  @override
  DeviceStatus status = DeviceStatus.idle;
  @override
  String? name;
  @override
  List<FoundDevice> found = const [];
  @override
  bool hasSearched = false;
  @override
  bool printing = false;
  @override
  String diagnosticReport = '';
  @override
  bool get connected => status == DeviceStatus.connected;
  int jobs = 0;
  int? lastCopies;
  Uint8List? lastPixels;
  LabelPaper? lastPaper;
  Completer<void>? completion;
  bool failPrint = false;
  @override
  Future<void> search() async {
    hasSearched = true;
    found = [
      FoundDevice(id: 'test-${model.name}', name: '${model.label}-TEST'),
    ];
    notifyListeners();
  }

  @override
  Future<void> stopSearch() async {}
  @override
  Future<void> pair(FoundDevice device) async {
    name = device.name;
    status = DeviceStatus.connected;
    found = const [];
    notifyListeners();
  }

  @override
  Future<void> connect({bool automatic = false}) async {
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
    name = null;
    await disconnect();
  }

  @override
  Future<void> printLabel(
    Uint8List pixels,
    LabelPaper paper, {
    int copies = 1,
  }) async {
    jobs++;
    lastCopies = copies;
    lastPixels = pixels;
    lastPaper = paper;
    printing = true;
    notifyListeners();
    try {
      await completion?.future;
      if (failPrint) throw StateError('Simulated printer error');
    } finally {
      printing = false;
      notifyListeners();
    }
  }
}
