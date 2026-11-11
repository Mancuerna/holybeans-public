import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/brew_water_plan.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  for (final ticks in [false, true]) {
    testWidgets('water plan isolates ${ticks ? 'timer ticks' : 'readings'}', (
      tester,
    ) async {
      final draft = BrewPoursDraft()
        ..bloomCount = 1
        ..pourCount = 2
        ..waterPlanBloomRatio = 3
        ..expandWaterPlan(true);
      final dose = TextEditingController(text: '18');
      final water = TextEditingController(text: '300');
      final minutes = TextEditingController();
      final seconds = TextEditingController();
      final watch = ManualStopwatch();
      final scale = FakeScale(name: 'Fixture', connected: true)..emit(0);
      final session = BrewScaleSession(scale, stopwatch: watch);
      final timer = BrewTimer(
        minutes: minutes,
        seconds: seconds,
        onStart: session.timerStarted,
        onStop: session.timerStopped,
        onReset: session.timerReset,
      );
      addTearDown(() {
        timer.dispose();
        session.dispose();
        scale.dispose();
        draft.dispose();
        for (final controller in [dose, water, minutes, seconds]) {
          controller.dispose();
        }
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BrewWaterPlan(
                draft: draft,
                dose: dose,
                water: water,
                timer: timer,
                scale: session,
                showTimer: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      timer.toggle();
      await tester.pumpAndSettle();
      scale.emit(0, timerRunning: true);
      await tester.pump();
      final dropdown = find.byKey(const ValueKey('water-plan-bloom-ratio'));
      final counts = await countWidgetRebuilds(
        {'dropdown': tester.element(dropdown)},
        () async {
          for (var i = 0; i < 100; i++) {
            if (ticks) {
              await tester.pump(const Duration(seconds: 1));
            } else {
              watch.elapsed = Duration(milliseconds: (i + 1) * 100);
              scale.emit(
                i.toDouble(),
                timerRunning: true,
                timerMs: (i + 1) * 100,
              );
              await tester.pump();
            }
          }
        },
      );
      stdout.writeln(
        'WATER_PLAN_REBUILDS ${jsonEncode({'ticks': ticks, ...counts})}',
      );
      expect(counts['dropdown'], 0);
      final tile = find.byKey(const ValueKey('brew-water-plan'));
      if (!ticks) {
        expect(session.pouredGrams, 99);
        expect(
          (tester.widget<ExpansionTile>(tile).subtitle! as Text).data,
          contains('177'),
        );
      }
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('water-plan-time'))).data,
        ticks ? '1:40' : '0:00',
      );
      water.text = '360';
      await tester.pump();
      expect(find.text('360 g'), findsOneWidget);
      if (!ticks) {
        expect(
          (tester.widget<ExpansionTile>(tile).subtitle! as Text).data,
          contains('207'),
        );
      }
      timer.stop();
      await tester.pump();
      expect(tester.widget<ExpansionTile>(tile).subtitle, isNull);
      timer.reset();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('water-plan-time'))).data,
        '0:00',
      );
      seconds.text = 'bad';
      await tester.pump();
      expect(timer.hasValidDuration, isFalse);
      expect(
        find.text('Enter whole minutes and seconds from 0 to 59.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
