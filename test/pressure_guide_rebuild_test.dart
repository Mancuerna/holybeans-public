import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_page.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/manual_stopwatch.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  testWidgets('pressure updates retain the page and timer controls', (
    tester,
  ) async {
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final sensor = FakePressureSensor(name: 'Fixture', connected: true);
    final watch = ManualStopwatch();
    final session = BrewPressureSession(sensor, stopwatch: watch);
    final timer = BrewTimer(
      minutes: minutes,
      seconds: seconds,
      onStart: session.timerStarted,
      onStop: session.timerStopped,
      onReset: session.timerReset,
    );
    addTearDown(() {
      timer.dispose();
      minutes.dispose();
      seconds.dispose();
      session.dispose();
      sensor.dispose();
    });
    final guide = PressureGuide.fromCurve(
      ShotCurve(timesMs: [0, 10000], pressure: [2, 8], weight: [], flow: []),
    )!;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: PressureGuidePage(
          guide: guide,
          title: 'Fixture reference',
          timer: timer,
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    timer.toggle();
    await tester.pump();
    final counts = await countWidgetRebuilds(
      {
        'page': tester.element(find.byType(PressureGuidePage)),
        'appBar': tester.element(find.byType(AppBar)),
        'title': tester.element(find.text('Fixture reference')),
        'toggle': tester.element(
          find.byKey(const ValueKey('pressure-guide-toggle')),
        ),
      },
      () async {
        for (var i = 0; i < 100; i++) {
          watch.elapsed = Duration(milliseconds: (i + 1) * 50);
          sensor.emit(i / 10);
          await tester.pump(const Duration(milliseconds: 50));
        }
      },
    );
    stdout.writeln('PRESSURE_GUIDE_BUILDS ${jsonEncode(counts)}');
    expect(counts, {'page': 0, 'appBar': 0, 'title': 0, 'toggle': 0});
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('pressure-actual'))).data,
      '9.9',
    );
    expect(timer.elapsedSeconds, 5);
    expect(
      tester
          .widget<PressureGuideChart>(find.byType(PressureGuideChart))
          .trace
          .last
          .bar,
      9.9,
    );
    timer.stop();
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    timer.reset();
    await tester.pump();
    expect(
      tester.widget<PressureGuideChart>(find.byType(PressureGuideChart)).trace,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
