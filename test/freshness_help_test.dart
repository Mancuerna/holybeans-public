import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/beans/freshness_help.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final locale in ['es', 'en']) {
    testWidgets('freshness help scrolls on a small screen in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(locale),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FreshnessHelp(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.byType(DataTable),
        300,
        scrollable: vertical,
      );
      await tester.pumpAndSettle();
      final verticalState = tester.state<ScrollableState>(vertical);
      verticalState.position.jumpTo(verticalState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      final state = tester.state<ScrollableState>(horizontal);
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.text(locale == 'es' ? 'Desde 91' : 'From 91').hitTestable(),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FreshnessHelp), findsNothing);
    });
  }
}
