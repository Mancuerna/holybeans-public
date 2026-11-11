import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/weight_targets.dart';

import 'helpers/paint_counts.dart';
import 'helpers/ui_test_support.dart';

ShotCurve _curve(bool empty) => ShotCurve(
  timesMs: empty ? [0] : [0, 1000, 2000],
  weight: empty ? [0] : [0, 10, 20],
  flow: empty ? [0] : [0, 1, 0],
  pressure: empty ? [0] : [0, 9, 0],
);

void main() {
  for (final empty in [true, false]) {
    testWidgets(
      '${empty ? 'empty' : 'recorded'} extraction retains equivalent paints',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final refresh = ValueNotifier(0);
        addTearDown(refresh.dispose);
        var curve = _curve(empty);
        final targets = [const WeightTarget(grams: 30, label: '30 g')];
        var clone = true;
        var compact = false;
        var unit = 'g/s';
        var targetWeight = 40.0;
        var fontSize = 12.0;
        var colors = ColorScheme.fromSeed(seedColor: Colors.brown);
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: refresh,
            builder: (_, _, _) => localizedApp(
              theme: ThemeData(
                colorScheme: colors,
                textTheme: TextTheme(labelSmall: TextStyle(fontSize: fontSize)),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ExtractionChart(
                    curve: curve,
                    compact: compact,
                    flowUnit: unit,
                    showReadout: false,
                    targetWeightGrams: targetWeight,
                    weightTargets: clone
                        ? [
                            for (final t in targets)
                              WeightTarget(
                                grams: t.grams,
                                label: t.label,
                                active: t.active,
                              ),
                          ]
                        : targets,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = find
            .descendant(
              of: find.byType(ExtractionChart),
              matching: find.byType(CustomPaint),
            )
            .last;
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
          '${empty ? 'EMPTY' : 'RECORDED'}_EXTRACTION_PAINTS $measured',
        );
        final invalidations = <String, bool>{};
        Future<void> changed(String name, VoidCallback change) async {
          final old = delegate();
          change();
          final count = await countPaints(target, () async {
            await update();
            await tester.pumpAndSettle();
          });
          expect(count, greaterThan(0), reason: name);
          invalidations[name] = delegate().shouldRepaint(old);
        }

        clone = false;
        await update();
        await changed(
          'target label',
          () => targets[0] = const WeightTarget(grams: 30, label: 'Goal'),
        );
        await changed(
          'target grams',
          () => targets[0] = const WeightTarget(grams: 35, label: 'Goal'),
        );
        await changed(
          'active target',
          () => targets[0] = const WeightTarget(
            grams: 35,
            label: 'Goal',
            active: true,
          ),
        );
        await changed('target weight', () => targetWeight = 45);
        await changed('flow unit', () => unit = 'ml/s');
        await changed('text style', () => fontSize = 14);
        await changed(
          'flow color',
          () => colors = colors.copyWith(primary: Colors.red),
        );
        await changed(
          'weight color',
          () => colors = colors.copyWith(onSurface: Colors.blue),
        );
        await changed(
          'label color',
          () => colors = colors.copyWith(onSurfaceVariant: Colors.green),
        );
        await changed(
          'grid',
          () => colors = colors.copyWith(outlineVariant: Colors.grey),
        );
        await changed(
          'background',
          () => colors = colors.copyWith(surface: Colors.yellow),
        );
        await changed(
          'region',
          () => tester.platformDispatcher.localeTestValue = const Locale(
            'es',
            'ES',
          ),
        );
        await changed('prepared curve', () => curve = _curve(false));
        final oldVisible = delegate();
        final visiblePaints = await countPaints(target, () async {
          await tester.tap(find.byKey(const ValueKey('curve-series-flow')));
          await tester.pumpAndSettle();
        });
        expect(visiblePaints, greaterThan(0));
        invalidations['visible series'] = delegate().shouldRepaint(oldVisible);
        await tester.tap(find.byKey(const ValueKey('curve-series-flow')));
        await tester.pumpAndSettle();
        final oldCompact = delegate();
        compact = true;
        await update();
        invalidations['compact'] = delegate().shouldRepaint(oldCompact);
        stdout.writeln('EXTRACTION_INVALIDATIONS $invalidations');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(invalidations.values, everyElement(isTrue));
        expect(measured, 0);
      },
    );
  }
}
