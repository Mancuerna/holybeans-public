import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_assistant_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/fake_scale.dart';

Future<void> checkPourAssistant(
  PatrolIntegrationTester $,
  AppDatabase db, {
  bool withScale = true,
}) async {
  final repo = JournalRepository(db);
  final coffee = await repo.createCoffee(
    name: 'Patrol pour bars',
    roaster: 'Patrol',
    initialGrams: 250,
  );
  final method = await repo.createMethod(name: 'V60', category: 'pourover');
  await repo.setMethodPourPlan(
    method,
    PourPlan(
      doseGrams: 15,
      ratio: 16,
      pours: 10,
      blooms: const [BloomStep(doseMultiple: 2, waitSeconds: 3)],
    ),
  );
  final scale = FakeScale(name: 'Patrol scale', connected: true)..emit(0);
  try {
    final coffees = await db.select(db.coffees).get();
    await $.pumpWidgetAndSettle(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: BrewForm(
                      services: AppServices.forJournal(
                        repo,
                        parameterSettings: BrewParameterSettings(db),
                        scale: withScale ? scale : null,
                      ),

                      coffees: coffees,
                      initialCoffeeId: coffee,
                      initialMethodId: method,
                      initialDoseGrams: 15,
                    ),
                  ),
                ),
              ),
              child: const Text('Open brew'),
            ),
          ),
        ),
      ),
    );
    await $.tap(find.text('Open brew'));
    final form = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('pour-assistant')),
      view: form,
    );
    await $.tap(find.byKey(const ValueKey('pour-assistant')));
    final editor = find
        .descendant(
          of: find.byType(PourAssistantPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await $.scrollUntilVisible(
      finder: find.byKey(const ValueKey('pour-start')),
      view: editor,
    );
    await $.tester.ensureVisible(
      find.byKey(const ValueKey('pour-mode-manual')),
    );
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('pour-mode-manual')));
    expect(
      $.tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('pour-mode-manual')))
          .selected,
      isTrue,
    );
    await $.tester.ensureVisible(find.byKey(const ValueKey('pour-start')));
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('pour-start')));
    if (!withScale) {
      await $.tap(find.byKey(const ValueKey('pour-finish')));
      await $.pumpAndSettle();
      await $.tap(find.text('Save').last);
      await $.pumpAndSettle();
      final brew = await db.select(db.brews).getSingle();
      expect(brew.bloomCount, 1);
      expect(brew.pourCount, 10);
      expect(brew.bloomSeconds, 3);
      expect(brew.pourPhasesJson, isNull);
      expect(await db.select(db.brewCurves).get(), isEmpty);
      return;
    }
    Future<void> sample(double grams) async {
      scale.emit(grams);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await $.tester.pump();
    }

    for (var i = 0; i < 8; i++) {
      await sample(0);
    }
    for (var i = 1; i <= 10; i++) {
      await sample(i * 3);
    }
    for (var i = 0; i < 8; i++) {
      await sample(30);
    }
    for (var i = 1; i <= 10; i++) {
      await sample(30 + i * 15);
    }
    for (var i = 0; i < 8; i++) {
      await sample(180);
    }
    await $.pumpAndSettle();
    expect(find.text('When you’re ready'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pour-current-step')),
        matching: find.text('Bloom 1'),
      ),
      findsOneWidget,
    );
    await $.takeNativeScreenshot('pour-manual-overdue');
    await $.tap(find.byKey(const ValueKey('pour-advance')));
    expect(find.text('Pour 1 of 10'), findsOneWidget);
    await $.tap(find.byKey(const ValueKey('pour-pause')));
    expect(
      $.tester
          .widget<FilledButton>(find.byKey(const ValueKey('pour-advance')))
          .onPressed,
      isNull,
    );
    await $.takeNativeScreenshot('pour-manual-paused');
    await $.tap(find.byKey(const ValueKey('pour-pause')));
    final scroll = find.byKey(const ValueKey('pour-bars-scroll'));
    await $.tester.ensureVisible(scroll);
    await $.pumpAndSettle();
    final viewport = $.tester.getRect(scroll);
    final bar = $.tester.getRect(find.byKey(const ValueKey('pour-bar-8')));
    expect(bar.left, greaterThanOrEqualTo(viewport.left));
    expect(bar.right, lessThanOrEqualTo(viewport.right));
    await $.takeNativeScreenshot('pour-bars-follow-weight');
    await $.tester.drag(scroll, const Offset(500, 0));
    await $.pumpAndSettle();
    expect(find.text('Follow pour'), findsOneWidget);
    await $.tap(find.byKey(const ValueKey('pour-follow')));
    await $.pumpAndSettle();
    await $.tap(find.byKey(const ValueKey('pour-finish')));
    await $.pumpAndSettle();
    final water = find.widgetWithText(TextFormField, 'Water (g)');
    await $.scrollUntilVisible(
      finder: water,
      view: form,
      scrollDirection: AxisDirection.up,
    );
    expect($.tester.widget<TextFormField>(water).controller!.text, '180');
    await $.takeNativeScreenshot('pour-bars-measured-result');
    await $.tap(find.text('Save').last);
    await $.pumpAndSettle();
    final brew = await db.select(db.brews).getSingle();
    expect(brew.waterGrams, 180);
    expect(brew.pourCount, 1);
    expect(brew.bloomCount, 1);
    expect(brew.pourPhasesJson, isNotNull);
    expect(await db.select(db.brewCurves).get(), hasLength(1));
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    scale.dispose();
  }
}
