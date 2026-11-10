import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/domain/label_graphic.dart';
import 'package:image_picker/image_picker.dart';

class LabelGraphicController extends ChangeNotifier {
  String? data;
  ui.Image? image;
  bool loading = false;
  bool failed = false;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load(String? value) async {
    final generation = ++_generation;
    data = value;
    image?.dispose();
    image = null;
    failed = false;
    loading = value != null;
    notifyListeners();
    if (value == null) return;
    try {
      final codec = await ui.instantiateImageCodec(LabelGraphic.bytes(value));
      try {
        final decoded = (await codec.getNextFrame()).image;
        if (_disposed || generation != _generation) {
          decoded.dispose();
          return;
        }
        image = decoded;
      } finally {
        codec.dispose();
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (!_disposed && generation == _generation) failed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> pick() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: LabelGraphic.maxDimension.toDouble(),
        maxHeight: LabelGraphic.maxDimension.toDouble(),
      );
      if (selected == null || _disposed) return;
      if (await selected.length() > 4 * 1024 * 1024) {
        throw const FormatException('Source image too large');
      }
      final prepared = await compute(
        LabelGraphic.prepare,
        await selected.readAsBytes(),
      );
      if (!_disposed) await load(prepared);
    } catch (error, stack) {
      reportError(error, stack);
      if (!_disposed) failed = true;
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    image?.dispose();
    super.dispose();
  }
}
