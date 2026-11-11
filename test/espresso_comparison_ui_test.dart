import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/comparison_plot.dart';
import 'package:holybeans/ui/brews/espresso_combined_plot.dart';
import 'package:holybeans/ui/brews/espresso_comparison_curves.dart';

import 'helpers/ui_test_support.dart';

void main() {
  ComparisonCurve curve({int end = 4000, String unit = 'g/s'}) =>
      ComparisonCurve(
        ShotCurve(
          timesMs: [0, 1000, end],
          weight: [0, 2, 8],
          pressure: [0, 9, 6],
          flow: [0, 2, 4],
        ),
        unit,
      );
  Widget app(Widget child, {String language = 'en', bool dark = false}) =>
      localizedApp(
        locale: Locale(language),
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      );

  testWidgets(
    'cursor reuses prepared samples and changed curves rebuild the timeline',
    (tester) async {
      final a = curve();
      final b = curve(end: 6000);
      final replacement = curve(end: 8000);
      await tester.pumpWidget(
        app(
          EspressoComparisonCurves(
            a: a,
            b: b,
            firstDripA: 1000,
            firstDripB: 2000,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final plot = tester.widget<EspressoCombinedPlot>(
        find.byType(EspressoCombinedPlot),
      );
      final original = plot.timeline.samples(
        CurveSeries.pressure,
        second: false,
      );
      plot.onChanged(2000);
      await tester.pump();
      final moved = tester.widget<EspressoCombinedPlot>(
        find.byType(EspressoCombinedPlot),
      );
      expect(moved.cursorMs, 2000);
      expect(
        identical(
          moved.timeline.samples(CurveSeries.pressure, second: false),
          original,
        ),
        isTrue,
      );
      await tester.pumpWidget(
        app(
          EspressoComparisonCurves(
            a: a,
            b: replacement,
            firstDripA: 1000,
            firstDripB: 2000,
          ),
        ),
      );
      await tester.pump();
      final replaced = tester.widget<EspressoCombinedPlot>(
        find.byType(EspressoCombinedPlot),
      );
      expect(replaced.timeline.maxMs, 8000);
      expect(
        identical(
          replaced.timeline.samples(CurveSeries.pressure, second: false),
          original,
        ),
        isFalse,
      );
      expect(replaced.cursorMs, 2000);
      await tester.tap(find.text('First drip').first);
      await tester.pumpAndSettle();
      final aligned = tester.widget<EspressoCombinedPlot>(
        find.byType(EspressoCombinedPlot),
      );
      expect(aligned.timeline.minMs, -2000);
      expect(aligned.timeline.maxMs, 6000);
      expect(aligned.cursorMs, 0);
    },
  );

  for (final language in ['es', 'en']) {
    testWidgets(
      'combined overview, separate panels and alignment at 320px with large text ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          app(
            EspressoComparisonCurves(
              a: curve(),
              b: curve(end: 6000),
              firstDripA: 1000,
              firstDripB: 2000,
              durationA: 16.9,
              durationB: 32.9,
              beverageA: 43.3,
              beverageB: 54.2,
            ),
            language: language,
            dark: language == 'es',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A  16.9 s'), findsOneWidget);
        expect(find.text('B  54.2 g'), findsOneWidget);
        expect(find.byType(EspressoCombinedPlot), findsOneWidget);
        expect(find.byType(ComparisonPlot), findsNothing);
        expect(
          find.byKey(const ValueKey('espresso-plot-both-weight')),
          findsNothing,
        );
        final pressure = find.byKey(const ValueKey('espresso-combined-plot'));
        await tester.ensureVisible(pressure);
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getRect(pressure).centerRight - const Offset(8, 0),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<EspressoCombinedPlot>(pressure).cursorMs,
          closeTo(6000, 1),
        );
        expect(
          find.byKey(const ValueKey('espresso-combined-value-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('espresso-combined-value-b')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('espresso-delta-pressure')),
          findsNothing,
        );
        final noA = tester
            .widget<Text>(
              find.byKey(const ValueKey('espresso-combined-value-a')),
            )
            .data!;
        expect(noA, contains(language == 'es' ? 'Sin dato' : 'Not recorded'));
        final drip = find.text(
          language == 'es' ? 'Primera gota' : 'First drip',
        );
        await tester.ensureVisible(drip);
        await tester.tap(drip);
        await tester.pumpAndSettle();
        final aligned = tester.widget<EspressoCombinedPlot>(pressure);
        expect(aligned.timeline.minMs, -2000);
        expect(aligned.timeline.maxMs, 4000);
        expect(aligned.cursorMs, 0);
        final separate = find.byKey(const ValueKey('espresso-separated-mode'));
        await tester.ensureVisible(separate);
        await tester.tap(separate);
        await tester.pumpAndSettle();
        expect(find.byType(ComparisonPlot), findsNWidgets(2));
        final weight = find.byKey(const ValueKey('espresso-weight-toggle'));
        await tester.ensureVisible(weight);
        await tester.tap(
          find.descendant(of: weight, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('espresso-plot-both-weight')),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<ComparisonPlot>(find.byType(ComparisonPlot))
              .every((p) => p.cursorMs == 0),
          isTrue,
        );
        final slider = find.byKey(const ValueKey('espresso-comparison-time'));
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(50, 0));
        await tester.pumpAndSettle();
        final cursors = tester
            .widgetList<ComparisonPlot>(find.byType(ComparisonPlot))
            .map((p) => p.cursorMs)
            .toSet();
        expect(cursors, hasLength(1));
        expect(cursors.single, isNot(0));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('mixed flow panels show each unit without a flow delta', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        EspressoComparisonCurves(
          a: curve(),
          b: curve(unit: 'ml/s'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final combined = tester.widget<EspressoCombinedPlot>(
      find.byType(EspressoCombinedPlot),
    );
    expect(combined.flowCompatible, isFalse);
    expect(find.text('A  4 g/s'), findsOneWidget);
    expect(find.text('B  4 ml/s'), findsOneWidget);
    expect(
      find.text('Flow uses different units and is shown separately.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('espresso-separated-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('espresso-plot-a-flow')), findsOneWidget);
    expect(find.byKey(const ValueKey('espresso-plot-b-flow')), findsOneWidget);
    expect(find.byKey(const ValueKey('espresso-delta-flow')), findsNothing);
    expect(
      find.byKey(const ValueKey('espresso-delta-pressure')),
      findsOneWidget,
    );
    final segments = tester.widget<SegmentedButton<ComparisonAlignment>>(
      find.byType(SegmentedButton<ComparisonAlignment>),
    );
    expect(segments.segments.last.enabled, isFalse);
  });
  testWidgets(
    'missing curves still give explicit messages without charts or alignment',
    (tester) async {
      await tester.pumpWidget(
        app(const EspressoComparisonCurves(a: null, b: null)),
      );
      expect(find.text('A: This brew has no saved curve.'), findsOneWidget);
      expect(find.text('B: This brew has no saved curve.'), findsOneWidget);
      expect(find.byType(ComparisonPlot), findsNothing);
      expect(find.byType(EspressoCombinedPlot), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.pumpWidget(
        app(EspressoComparisonCurves(a: curve(), b: null)),
      );
      expect(find.byType(EspressoCombinedPlot), findsOneWidget);
      expect(
        find.byKey(const ValueKey('espresso-combined-value-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('espresso-delta-pressure')),
        findsNothing,
      );
    },
  );
}
