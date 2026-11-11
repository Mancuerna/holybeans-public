import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';
import 'package:holybeans/ui/brews/espresso_combined_plot.dart';
import 'package:holybeans/ui/brews/espresso_comparison_curves.dart';

import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

ComparisonCurve _curve(double end) => ComparisonCurve(
  ShotCurve(
    timesMs: [0, 3000, 6000],
    weight: [0, end / 2, end],
    flow: [0, 2, 4],
    pressure: [0, 9, 6],
  ),
  'g/s',
);

void main() {
  for (final espresso in [false, true]) {
    testWidgets(
      '${espresso ? 'espresso' : 'filter'} replay retains static controls',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          localizedApp(
            locale: const Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: espresso
                    ? EspressoComparisonCurves(a: _curve(20.5), b: _curve(25))
                    : ComparisonCurves(a: _curve(20.5), b: _curve(25)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final play = find.byKey(const ValueKey('comparison-playback'));
        final slider = find.byKey(
          ValueKey(
            espresso ? 'espresso-comparison-time' : 'comparison-curve-time',
          ),
        );
        final readout = espresso
            ? find.byKey(const ValueKey('espresso-combined-value-a'))
            : find.textContaining(RegExp(r'^\d+:\d{2} {4}A: '));
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final start = tester.widget<Slider>(slider).value;
        final beforeText = tester.widget<Text>(readout).data;
        final controls = <String, Finder>{
          if (espresso) ...{
            'mode': find.byType(SegmentedButton<bool>),
            'alignment': find.byType(SegmentedButton<ComparisonAlignment>),
            'highlights': find.text('Peak pressure'),
          } else ...{
            'series': find.byKey(const ValueKey('comparison-series-weight')),
            'curveA': find.byKey(const ValueKey('comparison-curve-a')),
            'curveB': find.byKey(const ValueKey('comparison-curve-b')),
          },
        };
        final counts = await countWidgetRebuilds(
          {
            for (final entry in controls.entries)
              entry.key: tester.element(entry.value),
            'slider': tester.element(slider),
          },
          () async {
            for (var i = 0; i < 100; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
          },
        );
        stdout.writeln(
          '${espresso ? 'ESPRESSO' : 'FILTER'}_PLAYBACK_REBUILDS $counts',
        );
        expect(tester.widget<Slider>(slider).value, closeTo(start + 1600, 1));
        expect(tester.widget<Text>(readout).data, isNot(beforeText));
        if (espresso) {
          expect(
            tester
                .widget<EspressoCombinedPlot>(find.byType(EspressoCombinedPlot))
                .cursorMs,
            closeTo(start + 1600, 1),
          );
        }
        expect(counts['slider'], 100);
        await tester.tap(play);
        await tester.pump();
        final paused = tester.widget<Slider>(slider).value;
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.widget<Slider>(slider).value, paused);
        tester.platformDispatcher.localeTestValue = const Locale('es', 'ES');
        tester.widget<Slider>(slider).onChanged!(1950);
        await tester.pump();
        if (espresso) {
          expect(tester.widget<Slider>(slider).label, '1,95 s');
        } else {
          expect(tester.widget<Text>(readout).data, contains('10,3 g'));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        for (final name in controls.keys) {
          expect(counts[name], 0, reason: name);
        }
      },
    );
  }
}
