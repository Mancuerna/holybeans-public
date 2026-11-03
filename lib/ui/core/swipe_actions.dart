import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/ui/core/app_theme.dart';

/// One action behind a card, shown while it is dragged sideways.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.run,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() run;

  /// The main action, on the accent; the other one stays neutral.
  final bool primary;
}

/// Drag a card right for [start] or left for [end]. The card never leaves
/// the list: the action runs (asking first when it should) and the card
/// slides back, so the list only changes when the data does. The same
/// actions stay in the card's menu for those who do not swipe.
class SwipeActions extends StatelessWidget {
  const SwipeActions({
    super.key,
    required this.id,
    required this.child,
    this.start,
    this.end,
  });

  final String id;
  final Widget child;
  final SwipeAction? start;
  final SwipeAction? end;

  @override
  Widget build(BuildContext context) {
    if (start == null && end == null) return child;
    return Dismissible(
      key: ValueKey('swipe-$id'),
      direction: switch ((start, end)) {
        (_?, _?) => DismissDirection.horizontal,
        (_?, null) => DismissDirection.startToEnd,
        _ => DismissDirection.endToStart,
      },
      dismissThresholds: const {
        DismissDirection.startToEnd: .3,
        DismissDirection.endToStart: .3,
      },
      background: start == null
          ? const SizedBox.shrink()
          : _Behind(
              action: start!,
              alignment: AlignmentDirectional.centerStart,
            ),
      secondaryBackground: end == null
          ? null
          : _Behind(action: end!, alignment: AlignmentDirectional.centerEnd),
      confirmDismiss: (direction) async {
        final action = direction == DismissDirection.startToEnd ? start : end;
        if (action == null) return false;
        // Felt, not waited for: the action must not depend on the motor.
        HapticFeedback.mediumImpact().ignore();
        await action.run();
        return false;
      },
      child: child,
    );
  }
}

class _Behind extends StatelessWidget {
  const _Behind({required this.action, required this.alignment});

  final SwipeAction action;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = action.primary
        ? colors.primary
        : colors.surfaceContainerHighest;
    final foreground = action.primary ? colors.onPrimary : colors.onSurface;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, color: foreground),
          const SizedBox(width: 8),
          Text(
            action.label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
