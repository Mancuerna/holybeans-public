import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Shows the full button near either end of a list and only its icon in
/// between. Separate entry and exit margins avoid flickering at the edges.
class FloatingButtonExtension extends ValueNotifier<bool> {
  FloatingButtonExtension() : super(true);

  Timer? _idleTimer;
  bool? _pendingValue;
  bool _updateScheduled = false;
  bool _disposed = false;

  // Scrolling can start while the viewport applies new dimensions in layout.
  // Coalesce those updates until the frame ends, when listeners may rebuild.
  void _setExtended(bool extended) {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _pendingValue = null;
      value = extended;
      return;
    }
    _pendingValue = extended;
    if (_updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      final pending = _pendingValue;
      _pendingValue = null;
      if (!_disposed && pending != null) value = pending;
    });
  }

  /// Observes position throughout the gesture, irrespective of direction.
  bool onScroll(
    ScrollNotification notification, {
    bool expandWhenIdle = false,
  }) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical ||
        notification is UserScrollNotification) {
      return false;
    }
    _idleTimer?.cancel();
    final distance = metrics.extentBefore < metrics.extentAfter
        ? metrics.extentBefore
        : metrics.extentAfter;
    if (distance <= 24) {
      _setExtended(true);
    } else if (distance >= 72) {
      _setExtended(false);
    }
    if (expandWhenIdle && notification is ScrollEndNotification) {
      _idleTimer = Timer(
        const Duration(milliseconds: 300),
        () => _setExtended(true),
      );
    }
    return false;
  }

  void reset() {
    _idleTimer?.cancel();
    _setExtended(true);
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingValue = null;
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// Hides [child] while the keyboard is open, so the floating button does not
/// sit over the results the user is searching. It reads the inset itself:
/// only this widget rebuilds while the keyboard moves, not the tabs.
class HiddenWithKeyboard extends StatelessWidget {
  const HiddenWithKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0
      ? const SizedBox.shrink()
      : child;
}
