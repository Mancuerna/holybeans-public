import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saving without a scale preserves planned amounts through editing and backup', () async {
    final db = memoryDatabase();
    final copy = memoryDatabase();
    addTearDown(db.close);
    addTearDown(copy.close);
    final repo = JournalRepository(db);
    final coffee = await repo.createCoffee(
      name: 'Plan',
      roaster: 'R',
      initialGrams: 250,
    );
    final method = await repo.createMethod(name: 'V60', category: 'pourover');
    final model = BrewFormModel(
      repository: repo,
      settings: BrewParameterSettings(db),
      coffees: await repo.allCoffees(),
      initialCoffeeId: coffee,
      initialMethodId: method,
    );
    addTearDown(model.dispose);
    for (var i = 0; i < 100 && model.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    model.draft.dose.text = '18';
    model.draft.water.text = '300';
    model.draft.pours
      ..setCount(BrewPourKind.bloom, 1)
      ..setCount(BrewPourKind.pour, 3)
      ..expandWaterPlan(true)
      ..setWaterPlanBloomRatio(3);
    final outcome = await model.save();
    expect(outcome, isNotNull);
    final saved = (await repo.brew(outcome!.id))!;
    BrewPours details(Brew brew) => BrewPours.fromStorage(
      bloomCount: brew.bloomCount,
      pourCount: brew.pourCount,
      phasesJson: brew.pourPhasesJson,
    );
    expect(details(saved).phases.map((p) => p.waterGrams), [54, 82, 82, 82]);
    expect(details(saved).phases.every((p) => p.waterFromPlan), isTrue);
    for (final strings in [AppLocalizationsEs(), AppLocalizationsEn()]) {
      final shared = BrewShareText.build(
        strings: strings,
        coffee: (await repo.allCoffees()).single,
        components: [],
        brew: saved,
        fields: {BrewParameter.pourDetails},
      );
      expect(shared, contains(strings.pourWaterFromPlan));
      expect(shared, isNot(contains('g/s')));
    }
    expect(saved.bloomSeconds, isNull);
    expect(await repo.brewCurve(saved.id), isNull);
    final editor = BrewFormModel(
      repository: repo,
      settings: BrewParameterSettings(db),
      coffees: await repo.allCoffees(),
      existing: saved,
    );
    addTearDown(editor.dispose);
    for (var i = 0; i < 100 && editor.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    editor.draft.notes.text = 'Kept';
    await editor.save();
    expect((await repo.brew(saved.id))!.pourPhasesJson, saved.pourPhasesJson);
    await JournalBackup(copy).restoreJson(await JournalBackup(db).exportJson());
    final restored = (await JournalRepository(copy).brew(saved.id))!;
    expect(restored.pourPhasesJson, saved.pourPhasesJson);
    expect((await repo.coffeeLots(coffee)).single.remainingGrams, 232);
  });

  for (final language in ['es', 'en']) {
    testWidgets(
      'recorded details identify planned water without claiming a measured flow ($language)',
      (tester) async {
        final pours = BrewPours(
          bloomCount: 1,
          pourCount: 1,
          phases: const [
            BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              waterGrams: 36,
              waterFromPlan: true,
              durationSeconds: 10,
            ),
          ],
        );
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: Scaffold(
              body: ListView(
                children: [BrewPourDetails(pours: pours, doseGrams: 18)],
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('brew-recorded-pour-details')),
        );
        await tester.pumpAndSettle();
        final label = language == 'es'
            ? 'Agua según el reparto'
            : 'Water from breakdown';
        expect(find.textContaining(label), findsOneWidget);
        expect(find.textContaining('g/s'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
