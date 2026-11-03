import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:patrol/patrol.dart';

import 'support/smoke_support.dart';

void main() {
  patrolTest(
    'long espresso with feeder RPM and Brix saves through the form',
    tags: ['android', 'brix-feeder'],
    ($) async {
      final db = await openTestDatabase();
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        await repo.createCoffee(
          name: 'Brix beans',
          roaster: 'Fixture',
          initialGrams: 250,
        );
        await repo.createMethod(name: 'Espresso', category: 'espresso');
        await repo.createGrinder(
          name: 'Dual motor',
          hasAdjustableRpm: true,
          hasAdjustableFeederRpm: true,
        );
        await $.pumpWidgetAndSettle(
          HolyBeansApp(database: db, initialLocale: const Locale('en')),
        );
        await $.tap(find.text('Brew').last);
        final form = verticalScrollable(find.byType(BrewForm));
        Future<void> choose(String label, String value) async {
          final selector = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.decoration.labelText == label,
          );
          await $.scrollUntilVisible(finder: selector, view: form);
          await $.tap(selector);
          await $.tap(find.text(value).last);
        }

        await choose('Choose a method', 'Espresso');
        await choose('Grinder', 'Dual motor');
        for (final (label, value) in [
          ('RPM', '800'),
          ('Feeder RPM', '60'),
          ('Dose (g)', '20'),
        ]) {
          final field = find.widgetWithText(TextFormField, label);
          await $.scrollUntilVisible(finder: field, view: form);
          await $.enterText(field, value);
        }
        final slider = find.byKey(const ValueKey('brew-ratio-slider'));
        await $.scrollUntilVisible(finder: slider, view: form);
        expect($.tester.widget<Slider>(slider).max, 10);
        final beverage = find.widgetWithText(
          TextFormField,
          'Beverage weight (g)',
        );
        await $.scrollUntilVisible(finder: beverage, view: form);
        await $.enterText(beverage, '200');
        await $.scrollUntilVisible(
          finder: find.text('Measure in Brix'),
          view: form,
        );
        await $.tap(find.text('Measure in Brix'));
        final bx = find.widgetWithText(TextFormField, 'Brix (°Bx)');
        await $.scrollUntilVisible(finder: bx, view: form);
        await $.enterText(bx, '2');
        await $.takeNativeScreenshot('brix-feeder-before-save');
        await $.tap(find.text('Save').last);
        final brew = (await repo.allBrews()).single;
        expect(brew.feederRpm, 60);
        expect(brew.grindRpm, 800);
        expect(brew.brix, 2);
        expect(brew.brixFactor, 0.85);
        expect(brew.tdsPercent, 1.7);
        expect(brew.beverageGrams, 200);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
      }
    },
  );
}
