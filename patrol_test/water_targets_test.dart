import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/water_target_settings.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/brew_water_plan.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/filter_water_targets.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'water plan targets toggle and persist on the device',
    tags: ['android', 'water-targets'],
    ($) async {
      final settings = await WaterTargetSettings.open();
      await settings.save(true);
      final draft = BrewPoursDraft()
        ..bloomCount = 1
        ..pourCount = 3
        ..waterPlanBloomRatio = 5;
      draft.expandWaterPlan(true);
      final dose = TextEditingController(text: '18');
      final water = TextEditingController(text: '300');
      final minutes = TextEditingController();
      final seconds = TextEditingController();
      final timer = BrewTimer(minutes: minutes, seconds: seconds);
      final curve = ShotCurve(
        timesMs: const [0, 5000, 10000, 15000, 45000, 50000, 55000, 60000],
        weight: const [0, 30, 60, 90, 90, 95, 108, 122],
        flow: const [],
      );
      Widget page() => MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(title: const Text('V60 · 18 g → 300 g')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: draft,
              builder: (context, _) => Column(
                children: [
                  BrewWaterPlan(
                    draft: draft,
                    dose: dose,
                    water: water,
                    timer: timer,
                  ),
                  const SizedBox(height: 12),
                  FilterWaterTargets(
                    plan: draft.waterPlan(dose: 18, water: 300)!,
                    poured: 122,
                    builder: (targets) => ExtractionChart(
                      curve: curve,
                      height: 220,
                      weightTargets: targets,
                      showReadout: false,
                      replayable: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      try {
        await $.pumpWidgetAndSettle(page());
        expect(find.textContaining('Bloom 1 · 1:5'), findsOneWidget);
        final toggle = find.byKey(const ValueKey('water-targets-toggle'));
        await $.scrollUntilVisible(
          finder: toggle,
          view: find.byType(Scrollable).first,
        );
        expect(
          $.tester
              .widget<ExtractionChart>(find.byType(ExtractionChart))
              .weightTargets
              .map((t) => t.grams),
          [90, 160, 230, 300],
        );
        await $.takeNativeScreenshot('water-targets-visible');
        await $.tap(toggle);
        expect(
          $.tester
              .widget<ExtractionChart>(find.byType(ExtractionChart))
              .weightTargets,
          isEmpty,
        );
        expect(await (await WaterTargetSettings.open()).load(), isFalse);
        await $.pumpWidgetAndSettle(const MaterialApp(home: SizedBox.shrink()));
        await $.pumpWidgetAndSettle(page());
        await $.scrollUntilVisible(
          finder: toggle,
          view: find.byType(Scrollable).first,
        );
        expect($.tester.widget<Switch>(toggle).value, isFalse);
        await $.takeNativeScreenshot('water-targets-hidden');
        await $.tap(toggle);
        expect(await settings.load(), isTrue);
      } finally {
        await $.pumpWidgetAndSettle(const MaterialApp(home: SizedBox.shrink()));
        timer.dispose();
        draft.dispose();
        dose.dispose();
        water.dispose();
        minutes.dispose();
        seconds.dispose();
      }
    },
  );
}
