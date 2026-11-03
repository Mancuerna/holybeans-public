import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/smooth_floating_button.dart';

class BeanAddAction {
  const BeanAddAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.run,
  });
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback run;
}

/// A normal tap starts a blank form. Long press or the visible arrow opens
/// related ways to add a bean, with labels and a scrollable small-screen layout.
/// Folded ([extended] false) it shows only its icon; long press still opens
/// the other ways.
class BeanAddButton extends StatefulWidget {
  const BeanAddButton({
    super.key,
    required this.onManual,
    required this.actions,
    this.extended = true,
  });
  final VoidCallback onManual;
  final List<BeanAddAction> actions;
  final bool extended;

  @override
  State<BeanAddButton> createState() => _BeanAddButtonState();
}

class _BeanAddButtonState extends State<BeanAddButton> {
  bool _expanded = false;

  Future<void> _open(BuildContext context) async {
    if (_expanded) return;
    final s = AppLocalizations.of(context)!;
    final box = context.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    final bottom =
        MediaQuery.sizeOf(context).height - position.dy - box.size.height;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() => _expanded = true);
    final route = RawDialogRoute<BeanAddAction>(
      barrierLabel: s.cancel,
      barrierColor: Colors.black38,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 460),
      pageBuilder: (dialogContext, animation, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            // The Scaffold removes its bottom padding around the FAB; use
            // the dialog's inset, which its own SafeArea consumes instead.
            (bottom - MediaQuery.paddingOf(dialogContext).bottom)
                .clamp(16, 140)
                .toDouble(),
          ),
          child: Align(
            alignment: Alignment.bottomRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SingleChildScrollView(
                child: Column(
                  key: const ValueKey('bean-add-menu'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, action) in widget.actions.indexed)
                      _MenuArrival(
                        animation: animation,
                        order: widget.actions.length - index - 1,
                        count: widget.actions.length,
                        reduceMotion: reduceMotion,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FilledButton.tonalIcon(
                            key: ValueKey(action.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () =>
                                Navigator.pop(dialogContext, action),
                            icon: Icon(action.icon),
                            label: Text(action.label),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: box.size.width,
                      height: box.size.height,
                      child: FilledButton.icon(
                        key: const ValueKey('bean-add-close'),
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(s.cancel),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Individual entries own their motion; the route animates the scrim.
      transitionBuilder: (_, _, _, child) => child,
    );
    final chosen = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (!mounted) return;
    setState(() => _expanded = false);
    chosen?.run();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Opacity(
      opacity: _expanded ? 0 : 1,
      child: GestureDetector(
        onLongPress: () => _open(context),
        child: SmoothFloatingButton(
          key: const ValueKey('bean-add-manual'),
          isExtended: widget.extended,
          tooltip: widget.extended ? null : s.newBean,
          onPressed: widget.onManual,
          icon: const Icon(Icons.add_rounded),
          label: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 112).clamp(
                100,
                380,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    s.newBean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('bean-add-options'),
                  tooltip: s.beanAddOptions,
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.expand_less_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens from the bottom upwards and folds back in the reverse order.
class _MenuArrival extends StatelessWidget {
  const _MenuArrival({
    required this.animation,
    required this.order,
    required this.count,
    required this.reduceMotion,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final int count;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    final start = count <= 1 ? 0.0 : .35 * order / (count - 1);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final progress = Interval(
          start,
          start + .65,
        ).transform(animation.value);
        final motion = Curves.easeOutBack.transform(progress);
        return IgnorePointer(
          ignoring: progress < .8,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, (1 - motion) * (36 + order * 12)),
              child: Transform.scale(
                scale: .88 + .12 * motion,
                alignment: Alignment.centerRight,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
