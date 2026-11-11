import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'pour assistant follows method style without changing water ($language)',
      (tester) async {
        final db = memoryDatabase();
        final repo = JournalRepository(db);
        final ids = <String, String>{};
        for (final category in [
          'pourover',
          'immersion',
          'espresso',
          'percolation',
          'legacy',
        ]) {
          ids[category] = await repo.createMethod(
            name: category == 'immersion' ? 'V60 Switch closed' : category,
            category: category == 'legacy' ? null : category,
          );
        }
        final model = BrewFormModel(
          repository: repo,
          settings: BrewParameterSettings(db),
          coffees: const [],
        );
        addTearDown(() async {
          model.dispose();
          await tester.pumpAndSettle();
          await db.close();
        });
        var opened = 0;
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: model,
                  builder: (_, _) => BrewRecipeSection(
                    model: model,
                    actions: (
                      addMethod: () {},
                      addGrinder: () {},
                      addWaterProfile: () {},
                      manageTools: () {},
                      openPourAssistant: () => opened++,
                      importShot: (_) {},
                      importFreePour: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final assistant = find.byKey(const ValueKey('pour-assistant'));
        expect(assistant, findsNothing);
        model.draft.dose.text = '18';
        model.draft.water.text = '300';
        for (final category in [
          'pourover',
          'immersion',
          'pourover',
          'espresso',
          'percolation',
          'legacy',
          'immersion',
        ]) {
          final pending = model.selectMethod(ids[category]);
          await tester.pumpAndSettle();
          await pending;
          await tester.pumpAndSettle();
          final available = category != 'immersion' && category != 'espresso';
          expect(
            assistant,
            available ? findsOneWidget : findsNothing,
            reason: category,
          );
          expect(model.draft.water.text, '300');
          if (available) {
            await tester.ensureVisible(assistant);
            await tester.tap(assistant);
            await tester.pumpAndSettle();
          }
        }
        expect(opened, 4);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
