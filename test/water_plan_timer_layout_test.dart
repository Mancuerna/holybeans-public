import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/brew_water_plan.dart';

void main() {
  for (final (width, textScale, pours) in [(320.0, 2.0, 2), (390.0, 1.0, 10)]) {
    testWidgets(
      'plan clock remains accessible at $width / $textScale with $pours pours',
      (tester) async {
        tester.view.physicalSize = Size(width, pours == 2 ? 700 : 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final draft = BrewPoursDraft()
          ..bloomCount = 1
          ..pourCount = pours
          ..expandWaterPlan(true);
        final dose = TextEditingController(text: '18');
        final water = TextEditingController(text: '300');
        final bloom = TextEditingController();
        final minutes = TextEditingController();
        final seconds = TextEditingController();
        final timer = BrewTimer(minutes: minutes, seconds: seconds);
        addTearDown(() {
          timer.dispose();
          draft.dispose();
          for (final controller in [dose, water, bloom, minutes, seconds]) {
            controller.dispose();
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  const SizedBox(height: 700),
                  BrewWaterPlan(
                    draft: draft,
                    dose: dose,
                    water: water,
                    timer: timer,
                    bloom: bloom,
                    showTimer: true,
                  ),
                  const SizedBox(height: 700),
                ],
              ),
            ),
          ),
        );
        final toggle = find.byKey(const ValueKey('water-plan-timer-toggle'));
        await tester.scrollUntilVisible(toggle, 200);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(timer.running, isTrue);
        final viewport = tester.getRect(find.byType(Scrollable).first);
        final clock = tester.getRect(
          find.byKey(const ValueKey('water-plan-time')),
        );
        expect(clock.top, greaterThanOrEqualTo(viewport.top));
        expect(toggle.hitTestable(), findsOneWidget);
        final table = tester.getRect(
          find.byKey(const ValueKey('water-plan-table')),
        );
        expect(table.top, lessThan(viewport.bottom));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(timer.running, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
