import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/brew_water_plan.dart';

void main() {
  testWidgets(
    'folded planner calculates the reference and follows recipe edits',
    (tester) async {
      final draft = BrewPoursDraft()
        ..bloomCount = 2
        ..pourCount = 3
        ..waterPlanBloomRatio = 3;
      final dose = TextEditingController(text: '18');
      final water = TextEditingController(text: '297');
      final minutes = TextEditingController();
      final seconds = TextEditingController();
      final timer = BrewTimer(minutes: minutes, seconds: seconds);
      addTearDown(() {
        timer.dispose();
        draft.dispose();
        dose.dispose();
        water.dispose();
        minutes.dispose();
        seconds.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ListView(
                children: [
                  BrewWaterPlan(
                    draft: draft,
                    dose: dose,
                    water: water,
                    timer: timer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Reparto de agua · 297 g'), findsOneWidget);
      expect(find.byKey(const ValueKey('water-plan-table')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('brew-water-plan')));
      await tester.pumpAndSettle();
      expect(find.text('54 g'), findsNWidgets(3));
      expect(find.text('63 g'), findsNWidgets(3));
      expect(find.text('171 g'), findsOneWidget);
      expect(find.text('234 g'), findsOneWidget);
      expect(find.text('297 g'), findsOneWidget);
      expect(
        draft.value.phases,
        isEmpty,
        reason: 'planning must not invent measured phases',
      );
      water.text = '315';
      await tester.pumpAndSettle();
      expect(find.text('69 g'), findsNWidgets(3));
      water.text = '80';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('water-plan-table')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
