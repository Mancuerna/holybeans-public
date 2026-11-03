import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_add_button.dart';

void main() {
  Future<void> launch(
    WidgetTester tester,
    VoidCallback onChosen, {
    bool reduceMotion = false,
    bool navigationBar = false,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: navigationBar
            ? NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.coffee),
                    label: 'Beans',
                  ),
                ],
              )
            : null,
        floatingActionButton: BeanAddButton(
          onManual: () {},
          actions: [
            for (var i = 0; i < 4; i++)
              BeanAddAction(
                id: 'option-$i',
                icon: Icons.add,
                label: 'Option $i',
                run: onChosen,
              ),
          ],
        ),
      ),
    ),
  );

  for (final bottomInset in [0.0, 15.0, 24.0]) {
    testWidgets('close button stays anchored with inset $bottomInset', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.reset);
      await launch(tester, () {}, navigationBar: true);
      final button = find.byKey(const ValueKey('bean-add-manual'));
      final original = tester.getRect(button);
      await tester.tap(find.byKey(const ValueKey('bean-add-options')));
      await tester.pump();
      final close = find.byKey(const ValueKey('bean-add-close'));
      expect(tester.getRect(close), original);
      await tester.pumpAndSettle();
      expect(tester.getRect(close), original);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(tester.getRect(button), original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'options arrive from below in sequence and close before selection',
    (tester) async {
      var selections = 0;
      await launch(tester, () => selections++);
      await tester.tap(find.byKey(const ValueKey('bean-add-options')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final top = find.byKey(const ValueKey('option-0'));
      final bottom = find.byKey(const ValueKey('option-3'));
      final earlyTop = tester.getRect(top);
      final earlyBottom = tester.getRect(bottom);
      await tester.pumpAndSettle();
      final finalTop = tester.getRect(top);
      final finalBottom = tester.getRect(bottom);
      expect(
        earlyTop.top - finalTop.top,
        greaterThan(earlyBottom.top - finalBottom.top),
      );
      expect(earlyTop.width, lessThan(finalTop.width));
      expect(earlyBottom.top, greaterThan(finalBottom.top));
      await tester.tap(bottom);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.byKey(const ValueKey('bean-add-menu')), findsOneWidget);
      expect(selections, 0);
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(find.byKey(const ValueKey('bean-add-menu')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('bean-add-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bean-add-close')));
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion exposes actions immediately without displacement',
    (tester) async {
      var selections = 0;
      await launch(tester, () => selections++, reduceMotion: true);
      await tester.tap(find.byKey(const ValueKey('bean-add-options')));
      await tester.pump();
      final option = find.byKey(const ValueKey('option-0'));
      final first = tester.getRect(option);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(option), first);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
