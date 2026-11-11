import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/stats/stats_charts.dart';

import 'helpers/paint_counts.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final bars in [true, false]) {
    testWidgets(
      '${bars ? 'bars' : 'scatter'} retains equivalent chart paints',
      (tester) async {
        final refresh = ValueNotifier(0);
        addTearDown(refresh.dispose);
        final barData = [(label: 'A', value: 5.0, readout: 'Bar A')];
        final points = [(x: 1.0, y: 5.0, readout: 'Point A')];
        final marked = <int>{};
        var colors = ColorScheme.fromSeed(seedColor: Colors.brown);
        var scaler = TextScaler.noScaling;
        var fontSize = 12.0;
        var top = 10.0;
        var height = 200.0;
        var prefix = '';
        var xPrefix = '';
        var yPrefix = '';
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: refresh,
            builder: (_, _, _) => localizedApp(
              theme: ThemeData(
                colorScheme: colors,
                textTheme: TextTheme(labelSmall: TextStyle(fontSize: fontSize)),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scaler),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: bars
                        ? StatsBarChart(
                            bars: barData,
                            summary: 'Bars',
                            marked: marked,
                            height: height,
                            maxValue: top,
                            valueFormat: (v) => '$prefix$v',
                          )
                        : StatsScatter(
                            points: points,
                            summary: 'Points',
                            xLabel: 'X',
                            yLabel: 'Y',
                            xFormat: (v) => '$xPrefix$v',
                            yFormat: (v) => '$yPrefix$v',
                            yMax: top,
                            height: height,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = find.descendant(
          of: find.byType(bars ? StatsBarChart : StatsScatter),
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
          '${bars ? 'BARS' : 'SCATTER'}_UNCHANGED_PAINTS $measured',
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

        // Reusing caller collections must not hide edited values or marks.
        if (bars) {
          await changed(
            () => barData[0] = (label: 'A', value: 5.5, readout: 'Bar A'),
          );
          await changed(() => marked.add(0));
          await changed(() => prefix = '#');
          await changed(() => colors = colors.copyWith(tertiary: Colors.green));
          await changed(
            () => colors = colors.copyWith(tertiaryContainer: Colors.lime),
          );
          await changed(
            () =>
                colors = colors.copyWith(surfaceContainerHighest: Colors.grey),
          );
          await changed(
            () => colors = colors.copyWith(onSurface: Colors.black),
          );
        } else {
          await changed(() => points[0] = (x: 1.0, y: 5.5, readout: 'Point A'));
          // One point stays centered: changing X must still update axis labels.
          await changed(() => points[0] = (x: 2.0, y: 5.5, readout: 'Point A'));
          await changed(() => xPrefix = 'x');
          await changed(() => yPrefix = 'y');
          await changed(
            () => colors = colors.copyWith(outlineVariant: Colors.grey),
          );
          await changed(() => height = 220);
        }
        await changed(() => top = 11);
        await changed(() => colors = colors.copyWith(primary: Colors.red));
        await changed(
          () => colors = colors.copyWith(onSurfaceVariant: Colors.blue),
        );
        await changed(() => fontSize = 14);
        await changed(() => scaler = const TextScaler.linear(1.2));
        final old = delegate();
        final selectedPaints = await countPaints(target, () async {
          await tester.tapAt(tester.getCenter(paint));
          await tester.pumpAndSettle();
        });
        expect(selectedPaints, greaterThan(0));
        expect(delegate().shouldRepaint(old), true);
        expect(find.text(bars ? 'Bar A' : 'Point A'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(measured, 0);
      },
    );
  }
}
