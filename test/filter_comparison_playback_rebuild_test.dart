import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';

import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

ComparisonCurve _curve(double end) => ComparisonCurve(
  ShotCurve(
    timesMs: [0, 3000, 6000],
    weight: [0, end / 2, end],
    flow: [0, 2, 4],
  ),
  'g/s',
);

void main() {
  testWidgets(
    'filter replay retains static selectors while the cursor advances',
    (tester) async {
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ComparisonCurves(a: _curve(20), b: _curve(25)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final play = find.byKey(const ValueKey('comparison-playback'));
      final slider = find.byKey(const ValueKey('comparison-curve-time'));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final start = tester.widget<Slider>(slider).value;
      expect(find.textContaining('A: 0 g'), findsOneWidget);
      final counts = await countWidgetRebuilds(
        {
          'series': tester.element(
            find.byKey(const ValueKey('comparison-series-weight')),
          ),
          'curveA': tester.element(
            find.byKey(const ValueKey('comparison-curve-a')),
          ),
          'curveB': tester.element(
            find.byKey(const ValueKey('comparison-curve-b')),
          ),
          'slider': tester.element(slider),
        },
        () async {
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        },
      );
      stdout.writeln('FILTER_PLAYBACK_REBUILDS $counts');
      expect(tester.widget<Slider>(slider).value, closeTo(start + 1600, 1));
      expect(find.textContaining('A: 10 g'), findsOneWidget);
      expect(counts['slider'], 100);
      await tester.tap(play);
      await tester.pump();
      final paused = tester.widget<Slider>(slider).value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<Slider>(slider).value, paused);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(counts['series'], 0);
      expect(counts['curveA'], 0);
      expect(counts['curveB'], 0);
    },
  );
}
