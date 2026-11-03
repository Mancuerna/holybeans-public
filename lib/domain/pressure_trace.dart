/// One measured pressure point on the extraction clock. A break starts a new
/// segment after a pause, disconnection or a gap in notifications.
typedef PressureTracePoint = ({int elapsedMs, double bar, bool breakBefore});

/// Display-only pressure history; it never replaces a saved brew curve.
class PressureTrace {
  static const staleAfter = Duration(seconds: 2);
  final _points = <PressureTracePoint>[];
  List<PressureTracePoint>? _snapshot;
  bool _breakNext = true;

  List<PressureTracePoint> get points =>
      _snapshot ??= List.unmodifiable(_points);

  void breakSegment() => _breakNext = true;

  void add(int elapsedMs, double bar) {
    if (elapsedMs < 0 || !bar.isFinite || bar < 0 || bar > 30) {
      breakSegment();
      return;
    }
    final previous = _points.isEmpty ? null : _points.last;
    if (previous != null && elapsedMs < previous.elapsedMs) return;
    final gap =
        _breakNext ||
        previous == null ||
        elapsedMs - previous.elapsedMs >= staleAfter.inMilliseconds;
    final point = (elapsedMs: elapsedMs, bar: bar, breakBefore: gap);
    if (previous != null && previous.elapsedMs == elapsedMs) {
      _points[_points.length - 1] = (
        elapsedMs: elapsedMs,
        bar: bar,
        breakBefore: previous.breakBefore || gap,
      );
    } else {
      _points.add(point);
    }
    _breakNext = false;
    _snapshot = null;
  }

  void clear() {
    _points.clear();
    _snapshot = null;
    _breakNext = true;
  }
}
