import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_page.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['en', 'es']) {
    testWidgets(
      'guide follows shared timer, expires readings and exits ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final minutes = TextEditingController();
        final seconds = TextEditingController();
        final sensor = FakePressureSensor(name: 'BOOKOO', connected: true);
        final session = BrewPressureSession(sensor);
        final timer = BrewTimer(
          minutes: minutes,
          seconds: seconds,
          onStart: session.timerStarted,
          onStop: session.timerStopped,
          onReset: session.timerReset,
        );
        final guide = PressureGuide.fromCurve(
          ShotCurve(
            timesMs: [0, 2000, 4000],
            pressure: [2, 8, 6],
            flow: [],
            weight: [],
          ),
        )!;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            theme: ThemeData(
              brightness: language == 'es' ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(language == 'es' ? 2 : 1.3),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => PressureGuidePage(
                        guide: guide,
                        title: 'Reference',
                        timer: timer,
                        session: session,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final target = find.byKey(const ValueKey('pressure-target'));
        expect(
          tester.widget<Text>(target).data,
          language == 'en' ? '2.0' : '2,0',
        );
        final toggle = find.byKey(const ValueKey('pressure-guide-toggle'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(timer.elapsedSeconds, 2);
        expect(
          tester.widget<Text>(target).data,
          language == 'en' ? '8.0' : '8,0',
        );
        sensor.emit(7);
        await tester.pump();
        final actual = find.byKey(const ValueKey('pressure-actual'));
        expect(
          tester.widget<Text>(actual).data,
          contains(language == 'en' ? '7.0' : '7,0'),
        );
        final chart = tester.widget<PressureGuideChart>(
          find.byType(PressureGuideChart),
        );
        expect(chart.trace.single.bar, 7);
        expect(
          tester.getTopLeft(target).dy,
          language == 'en'
              ? tester.getTopLeft(actual).dy
              : lessThan(tester.getTopLeft(actual).dy),
        );
        await tester.pump(const Duration(seconds: 3));
        expect(tester.widget<Text>(actual).data, contains('—'));
        expect(tester.widget<Text>(target).data, '—');
        expect(
          timer.running,
          isTrue,
        ); // End of reference never stops extraction.
        sensor.emit(5);
        await tester.pump();
        await sensor.disconnect();
        await tester.pump();
        expect(tester.widget<Text>(actual).data, contains('—'));
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(timer.running, isFalse);
        expect(timer.elapsedSeconds, 5);
        final recorded = session.trace.points;
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PressureGuideChart>(find.byType(PressureGuideChart))
              .trace,
          recorded,
        );
        timer.reset();
        await tester.pump();
        expect(
          tester
              .widget<PressureGuideChart>(find.byType(PressureGuideChart))
              .trace,
          isEmpty,
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
  }
}
