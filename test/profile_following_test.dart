import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/profiles/profile_guide_chart.dart';
import 'package:holybeans/ui/profiles/profile_guide_page.dart';
import 'package:holybeans/ui/profiles/profile_guide_summary.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/ui_test_support.dart';

void main() {
  test('combined axes share time but scale each channel independently', () {
    final profile = ExtractionProfile.example('p', 'Both');
    final chart = ProfileGuideChart(
      profile: profile,
      elapsedMs: 32000,
      flowTrace: const [(elapsedMs: 31000, value: 8, breakBefore: true)],
      pressureTrace: const [(elapsedMs: 35000, value: 20, breakBefore: true)],
    );
    final axes = ProfileGuideAxes(chart, const Size(360, 250));
    expect(axes.maximumMs, 35000);
    expect(axes.flowMaximum, 8);
    expect(axes.pressureMaximum, 20);
    expect(axes.x(0), axes.area.left);
    expect(axes.x(35000), axes.area.right);
    expect(axes.y(4, flow: true), axes.y(10, flow: false));
    expect(axes.y(8, flow: true), axes.area.top);
    final pressureOnlyPeak = ProfileGuideAxes(
      ProfileGuideChart(profile: profile, elapsedMs: 0, pressureActual: 25),
      const Size(360, 250),
    );
    expect(pressureOnlyPeak.flowMaximum, 6);
    expect(pressureOnlyPeak.pressureMaximum, 25);
  });

  testWidgets(
    'combined guide keeps both readings visible and clears stale pressure',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sensor = FakePressureSensor(connected: true);
      final session = BrewPressureSession(sensor);
      final minutes = TextEditingController(text: '0');
      final seconds = TextEditingController(text: '10');
      final timer = BrewTimer(
        minutes: minutes,
        seconds: seconds,
        onStart: session.timerStarted,
        onStop: session.timerStopped,
      );
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('es'),
          home: ProfileGuidePage(
            profile: ExtractionProfile.example('p', 'Mi espresso'),
            timer: timer,
            pressure: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      timer.toggle();
      sensor.emit(6.3);
      await tester.pump();
      expect(find.text('6,3'), findsOneWidget);
      final summary = tester.widget<ProfileGuideSummary>(
        find.byType(ProfileGuideSummary),
      );
      expect(summary.pressureActual, 6.3);
      expect(summary.flowActual, isNull);
      expect(
        tester.getRect(find.byType(ProfileGuideChart)).bottom,
        lessThan(tester.getTopLeft(find.text('Detener')).dy),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        tester
            .widget<ProfileGuideChart>(find.byType(ProfileGuideChart))
            .pressureActual,
        isNull,
      );
      expect(
        tester
            .widget<ProfileGuideChart>(find.byType(ProfileGuideChart))
            .pressureTrace,
        isNotEmpty,
      );
      sensor.emit(7);
      await tester.pump();
      await sensor.disconnect();
      await tester.pump();
      expect(
        tester
            .widget<ProfileGuideSummary>(find.byType(ProfileGuideSummary))
            .pressureActual,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      timer.dispose();
      minutes.dispose();
      seconds.dispose();
      session.dispose();
      sensor.dispose();
    },
  );

  testWidgets('large text keeps combined controls and readings usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final timer = BrewTimer(minutes: minutes, seconds: seconds);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('es'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: ProfileGuidePage(
          profile: ExtractionProfile.example('p', 'Both'),
          timer: timer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    timer.dispose();
    minutes.dispose();
    seconds.dispose();
  });
}
