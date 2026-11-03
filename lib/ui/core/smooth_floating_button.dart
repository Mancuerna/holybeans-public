import 'package:flutter/material.dart';
import 'package:holybeans/ui/core/motion.dart';

/// Fades the label while smoothly changing the floating button’s width.
class SmoothFloatingButton extends StatelessWidget {
  const SmoothFloatingButton({
    super.key,
    required this.isExtended,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tooltip,
  });

  final bool isExtended;
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: isExtended ? 1 : 0, end: isExtended ? 1 : 0),
    duration: motionDuration(context, const Duration(milliseconds: 320)),
    curve: Curves.easeInOutCubic,
    child: label,
    builder: (context, extent, child) => FloatingActionButton.extended(
      tooltip: tooltip,
      onPressed: onPressed,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
      extendedIconLabelSpacing: 0,
      icon: icon,
      label: ClipRect(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: extent,
          child: IgnorePointer(
            ignoring: !isExtended,
            child: ExcludeSemantics(
              excluding: !isExtended,
              child: Offstage(
                offstage: extent == 0,
                child: Opacity(
                  opacity: extent,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
