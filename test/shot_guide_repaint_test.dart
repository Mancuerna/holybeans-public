import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('guide retains background until its axes or appearance change', (
    tester,
  ) async {
    final refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    var elapsed = 0;
    var actual = 3.0;
    var unit = 'bar';
    var minimum = 10.0;
    var locale = const Locale('en');
    var brightness = Brightness.light;
    var reference = <GuidePoint>[
      (elapsedMs: 0, value: 2, breakBefore: true),
      (elapsedMs: 10000, value: 8, breakBefore: false),
    ];
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: refresh,
        builder: (_, _, _) => localizedApp(
          locale: locale,
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: ShotGuideChart(
              reference: List.of(reference),
              target: 4,
              unit: unit,
              minimumMaximum: minimum,
              elapsedMs: elapsed,
              actual: actual,
              trace: [(elapsedMs: elapsed, value: actual, breakBefore: true)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paints = find.descendant(
      of: find.byType(ShotGuideChart),
      matching: find.byType(CustomPaint),
    );
    final background = tester.renderObject<RenderCustomPaint>(paints.first);
    final live = tester.renderObject<RenderCustomPaint>(paints.last);
    Future<Map<String, int>> count(Future<void> Function() action) async {
      final previous = debugOnProfilePaint;
      var backdropCount = 0;
      var liveCount = 0;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        if (identical(object, background)) backdropCount++;
        if (identical(object, live)) liveCount++;
      };
      try {
        await action();
        return {'background': backdropCount, 'live': liveCount};
      } finally {
        debugOnProfilePaint = previous;
      }
    }

    Future<void> update() async {
      refresh.value++;
      await tester.pump();
    }

    final measured = await count(() async {
      for (var i = 1; i <= 100; i++) {
        elapsed = i * 50;
        actual = 3 + i / 100;
        await update();
      }
    });
    stdout.writeln('GUIDE_PAINTS ${jsonEncode(measured)}');
    expect(measured, {'background': 0, 'live': 100});
    for (final change in <VoidCallback>[
      () => actual = 12,
      () => elapsed = 12000,
      () => reference = [
        ...reference,
        (elapsedMs: 15000, value: 6, breakBefore: true),
      ],
      () => unit = 'g/s',
      () => minimum = 20,
      () => locale = const Locale('es'),
    ]) {
      change();
      expect(await count(update), {'background': 1, 'live': 1});
    }
    brightness = Brightness.dark;
    final themePaints = await count(() async {
      await update();
      await tester.pumpAndSettle();
    });
    expect(themePaints['background'], greaterThan(0));
    expect(themePaints['live'], greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
