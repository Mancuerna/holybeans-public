import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/domain/prepared_curve.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/core/error_report.dart';

/// Large curves are prepared off the UI isolate. During live updates each
/// completed coherent snapshot is shown, with at most one newer input queued.
class CurveViewModel extends ChangeNotifier {
  CurveViewModel({Future<PreparedCurve> Function(CurveRequest)? prepare})
    : _prepare = prepare ?? _inBackground;

  final Future<PreparedCurve> Function(CurveRequest) _prepare;
  CurveRequest? _input;
  CurveRequest? _pending;
  PreparedCurve? value;
  Object? error;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  bool _live = false;

  static Future<PreparedCurve> _inBackground(CurveRequest request) =>
      compute(prepareCurve, request, debugLabel: 'extraction-curve');

  void update(ShotCurve curve, {int? firstDripMs, bool live = false}) {
    final request = (curve: curve, firstDripMs: firstDripMs);
    if (_disposed || (request == _input && live == _live)) return;
    _live = live;
    _input = request;
    error = null;
    if (curve.timesMs.length <= 500) {
      _generation++;
      _pending = null;
      value = prepareCurve(request);
      notifyListeners();
    } else {
      if (!live) {
        value = null;
        notifyListeners();
      }
      _pending = request;
      if (!_running) unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending != null) {
        final request = _pending!;
        final generation = _generation;
        _pending = null;
        try {
          final prepared = await _prepare(request);
          if (_disposed ||
              generation != _generation ||
              (!_live && request != _input)) {
            continue;
          }
          error = null;
          value = prepared;
          notifyListeners();
        } catch (failure, stack) {
          if (_disposed ||
              generation != _generation ||
              (!_live && request != _input)) {
            continue;
          }
          reportError(failure, stack);
          error = failure;
          notifyListeners();
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = _input = null;
    value = null;
    super.dispose();
  }
}
