import 'package:holybeans/domain/pour_plan.dart';

enum PourCue { short, long }

class ManualPourRun {
  ManualPourRun(PourPlan plan) : steps = List.unmodifiable(plan.steps);

  final List<PourStep> steps;
  int _index = 0;
  int _startedMs = 0;
  int? _lastCountdown;
  bool _reminded = false;

  bool get draining => _index == steps.length;
  PourStep? get current => draining ? null : steps[_index];
  PourStep? get next => _index + 1 < steps.length ? steps[_index + 1] : null;
  int get barSecond => (current ?? steps.last).startSecond;

  int? remainingSeconds(int elapsedMs) {
    final upcoming = next;
    if (upcoming == null) return null;
    final interval = upcoming.startSecond - current!.startSecond;
    final remainingMs = _startedMs + interval * 1000 - elapsedMs;
    return remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
  }

  void advance(int elapsedMs) {
    if (draining || elapsedMs < _startedMs) return;
    _index++;
    _startedMs = elapsedMs;
    _lastCountdown = null;
    _reminded = false;
  }

  PourCue? cueAt(int elapsedMs) {
    final left = remainingSeconds(elapsedMs);
    if (left == null || _reminded) return null;
    if (left == 0) {
      _reminded = true;
      return PourCue.long;
    }
    if (left <= 3 && left != _lastCountdown) {
      _lastCountdown = left;
      return PourCue.short;
    }
    return null;
  }
}
