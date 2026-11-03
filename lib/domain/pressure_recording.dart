import 'package:holybeans/domain/curve_sampling.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Pressure over a brew, keeping every timestamp so short peaks survive.
class PressureRecording {
  final _times = <int>[];
  final _bars = <double>[];
  ShotCurve? _base;
  ShotCurve? _combined;

  bool get isEmpty => _times.isEmpty;

  /// Highest pressure recorded, if any reading came in.
  double? get peakBar =>
      _bars.isEmpty ? null : _bars.reduce((top, bar) => bar > top ? bar : top);

  /// Readings at the same millisecond keep their highest pressure. Invalid
  /// and out-of-order readings are ignored; close timestamps are retained.
  void add(int elapsedMs, double bar) {
    if (elapsedMs < 0 || !bar.isFinite || bar < 0) return;
    if (_times.isNotEmpty && elapsedMs < _times.last) return;
    _combined = null;
    if (_times.isNotEmpty && elapsedMs == _times.last) {
      if (bar > _bars.last) _bars[_bars.length - 1] = bar;
      return;
    }
    _times.add(elapsedMs);
    _bars.add(bar);
  }

  void clear() {
    _times.clear();
    _bars.clear();
    _base = null;
    _combined = null;
  }

  /// Combines both timestamp sets, interpolating between readings and holding
  /// endpoints. Every original sample survives, including a pressure peak
  /// between scale notifications. Machine curves and empty inputs stay intact.
  ShotCurve addTo(ShotCurve curve) {
    if (_times.isEmpty || curve.isEmpty || curve.pressure.isNotEmpty) {
      return curve;
    }
    if (identical(_base, curve) && _combined != null) return _combined!;
    final times = {...curve.timesMs, ..._times}.toList()..sort();
    _base = curve;
    return _combined = ShotCurve(
      timesMs: times,
      pressure: resampleCurveSeries(_times, _bars, times),
      flow: resampleCurveSeries(curve.timesMs, curve.flow, times),
      weight: resampleCurveSeries(curve.timesMs, curve.weight, times),
    );
  }
}
