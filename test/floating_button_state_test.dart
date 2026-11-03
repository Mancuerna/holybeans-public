import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_add_button.dart';
import 'package:holybeans/ui/core/smooth_floating_button.dart';
import 'package:holybeans/ui/shell/floating_button_state.dart';

void main() {
  testWidgets('bean options return after rest and wait through another drag', (
    tester,
  ) async {
    final extension = FloatingButtonExtension();
    addTearDown(extension.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) =>
                extension.onScroll(notification, expandWhenIdle: true),
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 80, child: Text('Bean $i')),
              ],
            ),
          ),
          floatingActionButton: ValueListenableBuilder<bool>(
            valueListenable: extension,
            builder: (_, extended, _) => BeanAddButton(
              extended: extended,
              onManual: () {},
              actions: [
                BeanAddAction(
                  id: 'paste',
                  icon: Icons.paste,
                  label: 'Paste',
                  run: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    var gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(extension.value, isFalse);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(extension.value, isFalse);
    // Resuming before the delay expires must cancel the old expansion.
    gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(extension.value, isFalse);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(extension.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('bean-add-options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bean-add-menu')), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the floating button stays folded between either end of the list',
    (tester) async {
      final extension = FloatingButtonExtension();
      addTearDown(extension.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: extension.onScroll,
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 60; i++)
                    SizedBox(height: 80, child: Text('Card $i')),
                ],
              ),
            ),
            floatingActionButton: ValueListenableBuilder<bool>(
              valueListenable: extension,
              builder: (context, extended, _) => SmoothFloatingButton(
                isExtended: extended,
                tooltip: extended ? null : 'Brew',
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Brew'),
              ),
            ),
          ),
        ),
      );
      expect(extension.value, isTrue);
      expect(find.text('Brew'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(extension.value, isFalse);
      expect(find.text('Brew'), findsNothing);
      expect(find.byTooltip('Brew'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(extension.value, isFalse);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(extension.value, isTrue, reason: 'the end exposes all actions');
      expect(find.text('Brew'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(extension.value, isFalse, reason: 'leaving the bottom folds it');
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(extension.value, isFalse);
      // Small movements near either boundary keep the current size.
      for (final bottom in [false, true]) {
        double at(double distance) =>
            bottom ? controller.position.maxScrollExtent - distance : distance;
        for (final step in [
          (0.0, true),
          (40.0, true),
          (90.0, false),
          (40.0, false),
          (10.0, true),
        ]) {
          controller.jumpTo(at(step.$1));
          await tester.pumpAndSettle();
          expect(extension.value, step.$2);
        }
      }
      controller.jumpTo(500);
      await tester.pumpAndSettle();
      extension.reset();
      await tester.pumpAndSettle();
      expect(find.text('Brew'), findsOneWidget);
    },
  );

  for (final completion in ['latest', 'reset', 'dispose']) {
    testWidgets('layout scroll updates respect $completion before frame end', (
      tester,
    ) async {
      final extension = FloatingButtonExtension();
      final updates = <bool>[];
      extension.addListener(() => updates.add(extension.value));
      var laidOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LayoutBuilder(
            builder: (context, _) {
              if (!laidOut) {
                laidOut = true;
                void scroll(double pixels) => extension.onScroll(
                  ScrollUpdateNotification(
                    metrics: FixedScrollMetrics(
                      minScrollExtent: 0,
                      maxScrollExtent: 1000,
                      pixels: pixels,
                      viewportDimension: 200,
                      axisDirection: AxisDirection.down,
                      devicePixelRatio: 1,
                    ),
                    context: context,
                  ),
                );
                scroll(0);
                scroll(200);
                expect(
                  updates,
                  isEmpty,
                  reason: 'listeners must not rebuild during layout',
                );
                if (completion == 'reset') extension.reset();
                if (completion == 'dispose') extension.dispose();
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(updates, completion == 'latest' ? [false] : isEmpty);
      if (completion != 'dispose') extension.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('width changes gradually and reverses without a jump', (
    tester,
  ) async {
    final extended = ValueNotifier(true);
    addTearDown(extended.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ValueListenableBuilder<bool>(
            valueListenable: extended,
            builder: (_, value, _) => SmoothFloatingButton(
              isExtended: value,
              onPressed: () => taps++,
              icon: const Icon(Icons.add),
              label: const Text('Add water profile'),
            ),
          ),
        ),
      ),
    );
    Rect bounds() => tester.getRect(find.byType(FloatingActionButton));
    final full = bounds();
    extended.value = false;
    await tester.pump();
    expect(bounds().width, full.width);
    await tester.pump(const Duration(milliseconds: 120));
    final midway = bounds();
    expect(midway.width, lessThan(full.width));
    expect(midway.width, greaterThan(56));
    expect(midway.right, full.right);
    extended.value = true;
    await tester.pump();
    expect(bounds().width, midway.width);
    await tester.pumpAndSettle();
    expect(bounds(), full);
    extended.value = false;
    await tester.pumpAndSettle();
    expect(bounds().width, 56);
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the floating button hides while the keyboard is open', (
    tester,
  ) async {
    Widget app(double keyboard) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: const HiddenWithKeyboard(child: Text('Add bean')),
      ),
    );
    await tester.pumpWidget(app(0));
    expect(find.text('Add bean'), findsOneWidget);
    await tester.pumpWidget(app(300));
    expect(find.text('Add bean'), findsNothing);
  });
}
