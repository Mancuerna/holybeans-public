import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets(
    'Adjust from Home tunes the last brew with − and +, then offers to rate',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Tuned espresso',
        roaster: 'R',
        initialGrams: 250,
      );
      final method = await repository.createMethod(
        name: 'Lever',
        category: 'espresso',
      );
      await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'Lever',
        grindSetting: '0.5',
        doseGrams: 18,
        beverageGrams: 36,
        temperatureC: 90,
        timeSeconds: 28,
        rating: 7,
      );

      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('home-adjust-$coffee')));
      await tester.pumpAndSettle();

      expect(find.byType(BrewForm), findsOneWidget);
      expect(find.byKey(const ValueKey('brew-adjust-section')), findsOneWidget);
      // The rest of the form folds behind one entry.
      expect(find.byKey(const ValueKey('brew-full-form')), findsOneWidget);
      expect(find.text('Starting recipe: 0.5'), findsOneWidget);

      TextEditingController field(String key) => tester
          .widget<TextFormField>(find.byKey(ValueKey('$key-field')))
          .controller!;
      await tester.tap(find.byKey(const ValueKey('adjust-grind-less')));
      await tester.pump();
      expect(field('adjust-grind').text, '0.4');
      await tester.tap(find.byKey(const ValueKey('adjust-dose-more')));
      await tester.pump();
      expect(field('adjust-dose').text, '18.1');
      await tester.tap(find.byKey(const ValueKey('adjust-temperature-more')));
      await tester.pump();
      expect(field('adjust-temperature').text, '91');

      // The recipe above the fields follows the dose as it changes.
      final header = find.byKey(const ValueKey('brew-recipe-header'));
      expect(
        find.descendant(of: header, matching: find.textContaining('18.1 g')),
        findsWidgets,
      );

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final saved = (await database.select(database.brews).get()).firstWhere(
        (brew) => brew.rating == null,
      );
      expect(saved.grindSetting, '0.4');
      expect(saved.doseGrams, 18.1);
      expect(saved.temperatureC, 91);
      // Saved without a rating: the notice offers to rate it.
      expect(
        find.byKey(const ValueKey('brew-saved-rate-later')),
        findsOneWidget,
      );
      expect(find.text('Rate'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('the full form opens from Adjust with every section', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffee = await repository.createCoffee(
      name: 'Folded',
      roaster: 'R',
      initialGrams: 250,
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodName: 'V60',
      doseGrams: 15,
      waterGrams: 250,
    );
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('home-adjust-$coffee')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adjust-water-field')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('brew-full-form')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brew-full-form')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('brew-adjust-section')), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Water (g)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
