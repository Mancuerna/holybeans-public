import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settles animations while allowing real worker-isolate futures to complete.
/// The usual fake-clock pumpAndSettle cannot advance work in another isolate.
Future<void> settleWithWorkers(WidgetTester tester) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (elapsed.elapsed > const Duration(seconds: 30)) {
      throw StateError('UI did not settle while waiting for background work');
    }
  } while (tester.binding.hasScheduledFrame);
}

/// Taps a bottom navigation destination by position, as the labels may be
/// hidden on narrow screens.
Future<void> tapBottomDestination(WidgetTester tester, int index) async {
  final navigation = find.byType(NavigationBar);
  final bounds = tester.getRect(navigation);
  await tester.tapAt(
    Offset(bounds.left + bounds.width * (index + 0.5) / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
}

/// The first vertical scrollable inside [ancestor].
Finder verticalScrollable(Finder ancestor) => find
    .descendant(
      of: ancestor,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;
