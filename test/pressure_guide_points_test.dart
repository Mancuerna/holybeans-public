import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('pressure points are reused until their source changes', (
    tester,
  ) async {
    var guide = PressureGuide.fromCurve(
      ShotCurve(timesMs: [0, 10000], pressure: [2, 8], weight: [], flow: []),
    )!;
    final trace = PressureTrace()..add(0, 3);
    final elapsed = ValueNotifier(0);
    addTearDown(elapsed.dispose);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: elapsed,
            builder: (_, ms, _) => PressureGuideChart(
              guide: guide,
              elapsedMs: ms,
              actual: 3,
              trace: trace.points,
            ),
          ),
        ),
      ),
    );
    ShotGuideChart chart() => tester.widget(find.byType(ShotGuideChart));
    final initial = chart();
    var referenceCopies = 0;
    var traceCopies = 0;
    for (var i = 1; i <= 100; i++) {
      elapsed.value = i * 50;
      await tester.pump();
      if (!identical(chart().reference, initial.reference)) referenceCopies++;
      if (!identical(chart().trace, initial.trace)) traceCopies++;
    }
    stdout.writeln(
      'PRESSURE_POINT_COPIES ${jsonEncode({'reference': referenceCopies, 'trace': traceCopies})}',
    );
    expect(referenceCopies, 0);
    expect(traceCopies, 0);
    expect(chart().target, 5);
    expect(chart().elapsedMs, 5000);
    trace.add(5000, 6);
    elapsed.value++;
    await tester.pump();
    expect(chart().reference, same(initial.reference));
    expect(chart().trace, [
      (elapsedMs: 0, value: 3.0, breakBefore: true),
      (elapsedMs: 5000, value: 6.0, breakBefore: true),
    ]);
    final recorded = chart().trace;
    guide = PressureGuide.fromCurve(
      ShotCurve(timesMs: [0, 10000], pressure: [4, 10], weight: [], flow: []),
    )!;
    elapsed.value = 5000;
    await tester.pump();
    expect(chart().target, 7);
    expect(chart().reference.first.value, 4);
    expect(chart().trace, same(recorded));
    trace.clear();
    elapsed.value = 0;
    await tester.pump();
    expect(chart().trace, isEmpty);
    expect(chart().target, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
