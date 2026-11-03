import 'dart:math' as math;

import 'package:holybeans/domain/scale_recording.dart';

/// Keeps short changes of load out of an espresso's weight and flow.
/// A large step is held until the new load stays within 2 g for 500 ms.
/// Returning to the previous trajectory discards the held readings. These
/// generous thresholds are recording heuristics, not limits on extraction.
class EspressoScaleGuard {
  int? _lastMs;
  double? _lastGrams;
  int? _candidateMs;
  double? _candidateGrams;
  int _flowRecoveryUntilMs = -1;

  /// Null means a reading is invalid or a sudden load is still unconfirmed.
  /// Timer state is handled separately, including on rejected weight readings.
  ScaleReading? add(int elapsedMs, ScaleReading reading) {
    if (elapsedMs < 0 || !reading.grams.isFinite) return null;
    final beforeMs = _lastMs;
    final before = _lastGrams;
    if (beforeMs != null && elapsedMs < beforeMs) return null;
    final gap = beforeMs == null ? 0 : elapsedMs - beforeMs;
    final delta = before == null ? 0.0 : reading.grams - before;
    // Limit the comparison interval so waiting on a held step cannot make
    // that same step appear to be a gradual rise.
    final allowance = math.max(30.0, 100 * math.min(gap, 500) / 1000);
    if (before != null && delta.abs() > allowance) {
      _flowRecoveryUntilMs = elapsedMs + 1000;
      if (_candidateGrams == null ||
          (reading.grams - _candidateGrams!).abs() > 2) {
        _candidateMs = elapsedMs;
        _candidateGrams = reading.grams;
        return null;
      }
      if (elapsedMs - _candidateMs! < 500) return null;
    }
    _candidateMs = null;
    _candidateGrams = null;
    final measuredFlow = reading.flowGramsPerSecond;
    final useWeightFlow =
        elapsedMs <= _flowRecoveryUntilMs ||
        !measuredFlow.isFinite ||
        measuredFlow.abs() > 100;
    // The scale's native flow can trail a discarded load by about a second.
    // In that interval, use the change between accepted weight readings.
    final flow = useWeightFlow
        ? (gap > 0 ? math.max(0.0, delta * 1000 / gap) : 0.0)
        : measuredFlow;
    _lastMs = elapsedMs;
    _lastGrams = reading.grams;
    return ScaleReading(
      grams: reading.grams,
      flowGramsPerSecond: flow,
      timerMs: reading.timerMs,
      timerRunning: reading.timerRunning,
      timerAutoStopped: reading.timerAutoStopped,
      batteryPercent: reading.batteryPercent,
    );
  }

  void clear() {
    _lastMs = null;
    _lastGrams = null;
    _candidateMs = null;
    _candidateGrams = null;
    _flowRecoveryUntilMs = -1;
  }
}
