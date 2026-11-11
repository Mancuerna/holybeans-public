import 'package:flutter/widgets.dart';

/// Keeps an offscreen tab's widget until its inputs or selection change.
class RetainedJournalTab extends StatefulWidget {
  const RetainedJournalTab({
    super.key,
    required this.revision,
    required this.selected,
    required this.child,
  });

  final Object revision;
  final bool selected;
  final Widget child;

  @override
  State<RetainedJournalTab> createState() => _RetainedJournalTabState();
}

class _RetainedJournalTabState extends State<RetainedJournalTab> {
  late Widget _child = widget.child;

  @override
  void didUpdateWidget(RetainedJournalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Active tabs still refresh on every shell update, including date changes
    // when returning from a route. Hidden tabs receive new data immediately.
    if (widget.selected ||
        oldWidget.selected ||
        widget.revision != oldWidget.revision ||
        !Widget.canUpdate(oldWidget.child, widget.child)) {
      _child = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}
