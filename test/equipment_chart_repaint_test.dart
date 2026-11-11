import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/water_chart.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/paint_counts.dart';
import 'helpers/ui_test_support.dart';

WaterChartPoint _water(
  double gh, {
  WaterPointKind kind = WaterPointKind.profile,
}) => WaterChartPoint(
  id: 'water',
  label: 'Water',
  water: WaterComposition(measuredGh: gh, measuredKh: 20),
  kind: kind,
);

void main() {
  setUpAll(initializeDateFormatting);
  for (final piston in [true, false]) {
    testWidgets(
      '${piston ? 'piston' : 'water'} retains equivalent chart paints',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final refresh = ValueNotifier(0);
        addTearDown(refresh.dispose);
        final pistonPoints = [
          const PistonPoint(0, 1, 1.1, 0),
          const PistonPoint(1000, 1.2, 1.3, 0),
        ];
        final waterPoints = [_water(40)];
        var serviceTime = 500;
        var speed = false;
        var clone = true;
        var locale = const Locale('en');
        var scaler = TextScaler.noScaling;
        var colors = ColorScheme.fromSeed(seedColor: Colors.brown);
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: refresh,
            builder: (_, _, _) => localizedApp(
              locale: locale,
              theme: ThemeData(colorScheme: colors),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scaler),
                child: child!,
              ),
              home: Scaffold(
                body: piston
                    ? PistonChart(
                        points: clone
                            ? [
                                for (final p in pistonPoints)
                                  PistonPoint(
                                    p.timeMs,
                                    p.value,
                                    p.raw,
                                    p.cycle,
                                  ),
                              ]
                            : pistonPoints,
                        services: [
                          PistonService(
                            id: 'service',
                            timeMs: serviceTime,
                            kind: 'grease',
                          ),
                        ],
                        speed: speed,
                      )
                    : WaterChart(
                        points: clone
                            ? [
                                for (final p in waterPoints)
                                  _water(p.water.gh!, kind: p.kind),
                              ]
                            : waterPoints,
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = piston
            ? find.descendant(
                of: find.byType(PistonChart),
                matching: find.byType(CustomPaint),
              )
            : find.byKey(const ValueKey('water-scatter-chart'));
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
          '${piston ? 'PISTON' : 'WATER'}_UNCHANGED_PAINTS $measured',
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

        // Retaining a caller's list must not hide a later in-place replacement.
        clone = false;
        await update();
        if (piston) {
          await changed(
            () => pistonPoints[0] = const PistonPoint(0, 1, 1.5, 0),
          );
          await changed(
            () => pistonPoints[0] = const PistonPoint(0, 1.1, 1.5, 0),
          );
          await changed(
            () => pistonPoints[0] = const PistonPoint(0, 1.1, 1.5, 1),
          );
          await changed(
            () => pistonPoints[0] = const PistonPoint(100, 1.1, 1.5, 1),
          );
          await changed(() => serviceTime = 600);
          await changed(() => speed = true);
        } else {
          await changed(() => waterPoints[0] = _water(45));
          await changed(
            () => waterPoints[0] = _water(45, kind: WaterPointKind.target),
          );
          await changed(() => scaler = const TextScaler.linear(1.3));
          await changed(() => locale = const Locale('es'));
        }
        await changed(() => colors = colors.copyWith(primary: Colors.red));
        await changed(
          () => tester.platformDispatcher.localeTestValue = const Locale(
            'es',
            'ES',
          ),
        );
        final old = delegate();
        final selectedPaints = await countPaints(target, () async {
          if (piston) {
            await tester.tapAt(tester.getCenter(paint));
          } else {
            await tester.tap(find.byKey(const ValueKey('water-point-water')));
          }
          await tester.pumpAndSettle();
        });
        expect(selectedPaints, greaterThan(0));
        expect(delegate().shouldRepaint(old), true);
        if (!piston) {
          await changed(
            () => waterPoints[0] = WaterChartPoint(
              id: 'replacement',
              label: 'Water',
              water: waterPoints[0].water,
              kind: waterPoints[0].kind,
            ),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(measured, 0);
      },
    );
  }
}
