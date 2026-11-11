import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';
import 'helpers/widget_build_counts.dart';

void main() {
  testWidgets(
    'typing dose updates results without rebuilding unrelated sections',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Fixture',
        roaster: 'Test',
      );
      final method = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
      await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'Espresso',
        doseGrams: 18,
        beverageGrams: 36,
        tdsPercent: 10,
      );
      final brew = await database.select(database.brews).getSingle();
      final coffees = await repository.allCoffees();
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => BrewForm(
                    repository: repository,
                    settings: BrewParameterSettings(database),
                    coffees: coffees,
                    existing: brew,
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
      final model = tester
          .widget<BrewRecipeSection>(find.byType(BrewRecipeSection))
          .model;
      expect(model.busy, false);
      final counts = await countWidgetRebuilds(
        {
          'choice': tester.element(find.byType(BrewChoiceSection)),
          'equipment': tester.element(find.byType(BrewEquipmentSection)),
          'timing': tester.element(find.byType(BrewTimingSection)),
          'recipe': tester.element(find.byType(BrewRecipeSection)),
          'result': tester.element(find.byType(BrewResultSection)),
        },
        () async {
          for (var i = 0; i < 100; i++) {
            model.draft.dose.text = '18.$i';
            await tester.pump();
          }
        },
      );
      stdout.writeln('NUMERIC_FORM_REBUILDS $counts');
      model.draft.dose.text = '20';
      await tester.pump();
      expect(find.text('Ratio: 1:1.8'), findsOneWidget);
      expect(find.text('EY: 18 %'), findsOneWidget);
      model.draft.tds.text = '8';
      await tester.pump();
      expect(find.text('EY: 14.4 %'), findsOneWidget);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final saved = await database.select(database.brews).getSingle();
      expect(saved.doseGrams, 20);
      expect(saved.beverageGrams, 36);
      expect(saved.tdsPercent, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      expect(counts['recipe'], 100);
      expect(counts['result'], 100);
      for (final name in ['choice', 'equipment', 'timing']) {
        expect(counts[name], 0, reason: name);
      }
    },
  );
}
