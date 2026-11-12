import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';
import 'package:holybeans/ui/profiles/profile_editor_page.dart';
import 'package:holybeans/ui/profiles/profile_guide_page.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'editor validates and saves a named pressure-only profile on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ExtractionProfile? saved;
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ProfileEditorPage(
                      profile: ExtractionProfile.example('p', 'Example'),
                      onSave: (p) async {
                        saved = p;
                      },
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
      await tester.enterText(find.byType(TextFormField).first, 'My lever');
      await tester.tap(find.text('Target curves'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Flow'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved?.name, 'My lever');
      expect(saved?.flow, isEmpty);
      expect(saved?.pressure, isNotEmpty);
      expect(saved?.primary, 'pressure');
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('both guides share the clock and stop when leaving', (
    tester,
  ) async {
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final timer = BrewTimer(minutes: minutes, seconds: seconds);
    addTearDown(() {
      timer.dispose();
      minutes.dispose();
      seconds.dispose();
    });
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileGuidePage(
                    profile: ExtractionProfile.example('p', 'Both'),
                    timer: timer,
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
    timer.toggle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final charts = tester
        .widgetList<ShotGuideChart>(find.byType(ShotGuideChart))
        .toList();
    expect(charts.length, 2);
    expect(charts[0].elapsedMs, charts[1].elapsedMs);
    expect(charts[0].elapsedMs, greaterThanOrEqualTo(2000));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(timer.running, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pressure-only guide shows the explicit cup target', (
    tester,
  ) async {
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    final timer = BrewTimer(minutes: minutes, seconds: seconds);
    final profile = ExtractionProfile.example(
      'p',
      'Pressure',
    ).copyWith(flow: [], primary: 'pressure', targetGrams: 36);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: ProfileGuidePage(profile: profile, timer: timer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('— / 36.0 g'), findsOneWidget);
    expect(
      tester
          .widgetList<ShotGuideChart>(find.byType(ShotGuideChart))
          .single
          .unit,
      'bar',
    );
    await tester.pumpWidget(const SizedBox());
    timer.dispose();
    minutes.dispose();
    seconds.dispose();
  });
}
