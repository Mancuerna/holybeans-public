import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/comparison_curves.dart';
import 'package:holybeans/ui/brews/comparison_plot.dart';

import 'helpers/paint_counts.dart';
import 'helpers/ui_test_support.dart';

ComparisonCurve _curve(double end) => ComparisonCurve(
  ShotCurve(timesMs: [0, 1000, 2000], weight: [0, 2, end], flow: []),
  'g/s',
);

void main() {
  for (final filter in [true, false]) {
    testWidgets(
      '${filter ? 'filter' : 'espresso'} retains equivalent comparison paints',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final refresh = ValueNotifier(0);
        addTearDown(refresh.dispose);
        final a = _curve(8);
        final b = _curve(10);
        final first = <ComparisonPoint>[
          (timeMs: 0, value: 0),
          (timeMs: 2000, value: 8),
        ];
        final second = <ComparisonPoint>[
          (timeMs: 0, value: 0),
          (timeMs: 2000, value: 10),
        ];
        var clone = true;
        var cursor = 0.0;
        var min = 0.0;
        var max = 2000.0;
        var colors = ColorScheme.fromSeed(seedColor: Colors.brown);
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: refresh,
            builder: (_, _, _) => localizedApp(
              theme: ThemeData(colorScheme: colors),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: filter
                      ? ComparisonCurves(
                          a: clone ? _curve(8) : a,
                          b: clone ? _curve(10) : b,
                        )
                      : ComparisonPlot(
                          first: clone ? [...first] : first,
                          second: clone ? [...second] : second,
                          minMs: min,
                          maxMs: max,
                          cursorMs: cursor,
                          color: colors.primary,
                          locale: 'en',
                          label: 'Comparison',
                          onChanged: (value) {
                            cursor = value;
                            refresh.value++;
                          },
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = find.descendant(
          of: filter
              ? find.byKey(const ValueKey('comparison-plot-a-weight'))
              : find.byType(ComparisonPlot),
          matching: find.byType(CustomPaint),
        );
        final target = tester.renderObject<RenderCustomPaint>(paint);
        CustomPainter delegate() => tester.widget<CustomPaint>(paint).painter!;
        Future<void> update() async {
          refresh.value++;
          await tester.pump();
        }

        final measured = await countPaints(target, () async {
          for (var i = 0; i < 100; i++) {
            await update();
          }
        });
        stdout.writeln(
          '${filter ? 'FILTER' : 'ESPRESSO'}_UNCHANGED_PAINTS $measured',
        );
        Future<void> changed(VoidCallback change) async {
          final old = delegate();
          change();
          final count = await countPaints(target, () async {
            await update();
            await tester.pumpAndSettle();
          });
          expect(count, greaterThan(0));
          expect(delegate().shouldRepaint(old), true);
        }

        clone = false;
        await update();
        if (filter) {
          await changed(() => a.curve.weight[1] = 3);
          await changed(() => b.curve.weight[1] = 4);
          await changed(() => a.curve.timesMs[2] = 3000);
          await changed(
            () => colors = colors.copyWith(onSurface: Colors.black),
          );
          await changed(
            () => tester.widget<Slider>(find.byType(Slider)).onChanged!(500),
          );
        } else {
          await changed(() => first[1] = (timeMs: 2000, value: 9));
          await changed(() => second[1] = (timeMs: 2000, value: 11));
          await changed(() => min = -1000);
          await changed(() => max = 3000);
          await changed(() => cursor = 500);
          final old = delegate();
          await tester.tapAt(tester.getCenter(paint));
          await tester.pump();
          expect(cursor, isNot(500));
          expect(delegate().shouldRepaint(old), true);
        }
        await changed(() => colors = colors.copyWith(primary: Colors.red));
        await changed(
          () => colors = colors.copyWith(outlineVariant: Colors.grey),
        );
        await changed(
          () => colors = colors.copyWith(onSurfaceVariant: Colors.blue),
        );
        await changed(
          () => tester.platformDispatcher.localeTestValue = const Locale(
            'es',
            'ES',
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(measured, 0);
      },
    );
  }
}
