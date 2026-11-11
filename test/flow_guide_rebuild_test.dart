import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/flow_guide_page.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  testWidgets('flow updates retain the page and timer controls', (
    tester,
  ) async {
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final scale = FakeScale(name: 'Fixture', connected: true);
    final watch = ManualStopwatch();
    final session = BrewScaleSession(
      scale,
      stopwatch: watch,
      clock: () => DateTime(2026).add(watch.elapsed),
    );
    final timer = BrewTimer(
      minutes: minutes,
      seconds: seconds,
      onStart: session.timerStarted,
      onStop: session.timerStopped,
      onReset: session.timerReset,
    );
    session.requestStop = (_) => timer.stop();
    addTearDown(() {
      timer.dispose();
      minutes.dispose();
      seconds.dispose();
      session.dispose();
      scale.dispose();
    });
    final guide = FlowGuide.fromCurve(
      ShotCurve(
        timesMs: [for (var ms = 0; ms <= 10000; ms += 500) ms],
        weight: [for (var ms = 0; ms <= 10000; ms += 500) ms / 500],
        flow: [],
      ),
    )!;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: FlowGuidePage(
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
    scale.emit(0, timerRunning: true);
    await tester.pump();
    final toggle = find.byKey(const ValueKey('flow-guide-toggle'));
    final counts = await countWidgetRebuilds(
      {
        'page': tester.element(find.byType(FlowGuidePage)),
        'appBar': tester.element(find.byType(AppBar)),
        'title': tester.element(find.text('Fixture reference')),
        'toggle': tester.element(toggle),
      },
      () async {
        for (var i = 1; i <= 100; i++) {
          watch.elapsed = Duration(milliseconds: i * 100);
          scale.emit(i / 5, timerRunning: true, timerMs: i * 100);
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );
    stdout.writeln('FLOW_GUIDE_BUILDS ${jsonEncode(counts)}');
    expect(counts, {'page': 0, 'appBar': 0, 'title': 0, 'toggle': 0});
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('flow-actual'))).data,
      '2.0',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('flow-guide-weight'))).data,
      '20.0 / 20.0 g',
    );
    expect(timer.elapsedSeconds, 10);
    await scale.disconnect();
    await tester.pump();
    expect(timer.running, isFalse);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
