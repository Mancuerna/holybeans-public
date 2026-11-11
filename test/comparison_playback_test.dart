import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';
import 'package:holybeans/ui/brews/espresso_combined_plot.dart';
import 'package:holybeans/ui/brews/espresso_comparison_curves.dart';

import 'helpers/ui_test_support.dart';

ComparisonCurve curve(int end) => ComparisonCurve(
  ShotCurve(
    timesMs: [0, 1000, end],
    weight: [0, 2, 8],
    pressure: [0, 9, 6],
    flow: [0, 2, 4],
  ),
  'g/s',
);

Widget app(Widget child) => localizedApp(
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  for (final espresso in [true, false]) {
    testWidgets(
      '${espresso ? 'espresso' : 'filter'} plays, pauses, seeks and restarts',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final a = curve(4000);
        final b = curve(6000);
        Widget comparison(ComparisonCurve second) => espresso
            ? EspressoComparisonCurves(a: a, b: second)
            : ComparisonCurves(a: a, b: second);
        await tester.pumpWidget(app(comparison(b)));
        final play = find.byKey(const ValueKey('comparison-playback'));
        final slider = find.byKey(
          ValueKey(
            espresso ? 'espresso-comparison-time' : 'comparison-curve-time',
          ),
        );
        double position() => tester.widget<Slider>(slider).value;
        Future<void> toggle() async {
          await tester.ensureVisible(play);
          await tester.tap(play);
          await tester.pump();
        }

        await toggle();
        await tester.pump(const Duration(seconds: 1));
        expect(position(), closeTo(1000, 1));
        expect(find.byTooltip('Pause comparison'), findsOneWidget);
        if (espresso) {
          expect(
            tester
                .widget<EspressoCombinedPlot>(find.byType(EspressoCombinedPlot))
                .cursorMs,
            position(),
          );
        }
        await toggle();
        final paused = position();
        await tester.pump(const Duration(seconds: 1));
        expect(position(), paused);
        await toggle();
        await tester.pump(const Duration(milliseconds: 500));
        expect(position(), closeTo(paused + 500, 1));
        tester.widget<Slider>(slider).onChanged!(3000);
        await tester.pump(const Duration(seconds: 1));
        expect(position(), 3000);
        expect(find.byTooltip('Play comparison'), findsOneWidget);
        await toggle();
        await tester.pump(const Duration(seconds: 4));
        expect(position(), 6000);
        expect(find.byTooltip('Play comparison'), findsOneWidget);
        await toggle();
        expect(position(), 0);
        await tester.pump(const Duration(milliseconds: 500));
        expect(position(), closeTo(500, 1));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        final background = position();
        await tester.pump(const Duration(seconds: 1));
        expect(position(), background);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.byTooltip('Play comparison'), findsOneWidget);
        await toggle();
        await tester.pumpWidget(app(comparison(curve(8000))));
        expect(find.byTooltip('Play comparison'), findsOneWidget);
        await toggle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'first-drip replay includes negative time and chart touch pauses',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          EspressoComparisonCurves(
            a: curve(4000),
            b: curve(6000),
            firstDripA: 1000,
            firstDripB: 2000,
          ),
        ),
      );
      final play = find.byKey(const ValueKey('comparison-playback'));
      final chart = find.byType(EspressoCombinedPlot);
      EspressoCombinedPlot plot() => tester.widget<EspressoCombinedPlot>(chart);
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('First drip').first);
      await tester.pumpAndSettle();
      expect(plot().cursorMs, 0);
      expect(find.byTooltip('Play comparison'), findsOneWidget);
      plot().onChanged(plot().timeline.maxMs.toDouble());
      await tester.pump();
      await tester.tap(play);
      await tester.pump();
      expect(plot().cursorMs, -2000);
      await tester.pump(const Duration(seconds: 1));
      expect(plot().cursorMs, closeTo(-1000, 1));
      plot().onChanged(1500);
      await tester.pump(const Duration(seconds: 1));
      expect(plot().cursorMs, 1500);
      expect(find.byTooltip('Play comparison'), findsOneWidget);
    },
  );
}
