import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets(
    'memory is not a change; timer survives keep editing and discard preserves inventory',
    (tester) async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      final coffee = await repo.createCoffee(
        name: 'Guarded brew',
        roaster: 'Test',
        initialGrams: 250,
      );
      final method = await repo.createMethod(name: 'V60', category: 'pourover');
      await repo.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        methodId: method,
        doseGrams: 18,
        waterGrams: 288,
        timeSeconds: 150,
      );
      final coffees = await db.select(db.coffees).get();
      final beforeLots = await db.select(db.coffeeLots).get();
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFormSheet<BrewFormResult>(
                  context,
                  BrewForm(
                    repository: repo,
                    settings: BrewParameterSettings(db),
                    coffees: coffees,
                    initialCoffeeId: coffee,
                    initialMethodId: method,
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BrewForm), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final timer = find.byKey(const ValueKey('extraction-timer'));
      final scroll = find
          .descendant(
            of: find.byType(BrewForm),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(timer, 250, scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(timer);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep-editing')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('keep-editing')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(timer).onPressed, isNotNull);
      expect(find.text('Stop'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discard-changes')));
      await tester.pumpAndSettle();
      expect(find.byType(BrewForm), findsNothing);
      expect(await db.select(db.brews).get(), hasLength(1));
      expect(await db.select(db.coffeeLots).get(), beforeLots);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
