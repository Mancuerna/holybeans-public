import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets(
    'editing preserves values and distinguishes unspecified from pre-ground',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Brew edit regression',
        roaster: 'Test roaster',
      );
      final methodId = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      final grinderId = await repository.createGrinder(name: 'Comandante C40');
      final toolId = await repository.createMethodTool(
        methodId: methodId,
        name: 'Dose funnel',
      );
      final brewedAt = DateTime(2026, 9, 26, 16, 30);
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        methodId: methodId,
        grinderName: 'Comandante C40',
        grinderId: grinderId,
        grindSetting: '24 clicks',
        methodToolIds: [toolId],
        doseGrams: 18,
        waterGrams: 270,
        temperatureC: 93.5,
        beverageGrams: 36,
        timeSeconds: 150,
        tdsPercent: 8.2,
        rating: 4.5,
        notes: 'Sweet, clear finish',
        brewedAt: brewedAt,
      );

      final beforeCoffees = await database.select(database.coffees).get();
      final beforeLots = await database.select(database.coffeeLots).get();
      final beforeComponents = await database
          .select(database.coffeeComponents)
          .get();
      final beforeBrews = await database.select(database.brews).get();
      final beforeMethods = await database.select(database.brewMethods).get();
      final beforeGrinders = await database.select(database.grinders).get();
      final beforeMethodTools = await database
          .select(database.methodTools)
          .get();
      final beforeBrewToolSelections = await database
          .select(database.brewToolSelections)
          .get();
      expect(beforeMethodTools.single.id, toolId);
      expect(beforeBrewToolSelections.single.toolId, toolId);
      expect(
        await repository.methodTools(methodId, includeArchived: true),
        hasLength(1),
      );

      try {
        await tester.pumpWidget(
          HolyBeansApp(database: database, initialLocale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Brews').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit').last);
        await tester.pumpAndSettle();

        expect(find.byType(BrewForm), findsOneWidget);
        final form = find.byType(BrewForm);
        final scrollable = find
            .descendant(of: form, matching: find.byType(Scrollable))
            .first;

        expect(
          tester.widget<CoffeePicker>(find.byType(CoffeePicker)).value,
          coffeeId,
        );

        final methodDropdownFinder = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Choose a method',
        );
        final grinderDropdownFinder = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Grinder',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(methodDropdownFinder)
              .initialValue,
          methodId,
        );
        expect(
          find.descendant(
            of: find.byType(BrewForm),
            matching: find.byType(FilterChip),
          ),
          findsOneWidget,
        );
        final toolChip = find.widgetWithText(FilterChip, 'Dose funnel');
        expect(tester.widget<FilterChip>(toolChip).selected, isTrue);
        await tester.scrollUntilVisible(
          grinderDropdownFinder,
          240,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(grinderDropdownFinder)
              .initialValue,
          grinderId,
        );

        Future<void> expectPrefilled(String label, String value) async {
          final field = find.widgetWithText(TextFormField, label);
          await tester.scrollUntilVisible(field, 240, scrollable: scrollable);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(field).controller!.text,
            value,
            reason: '$label should be prefilled from the saved brew',
          );
        }

        await expectPrefilled('Grind setting', '24 clicks');
        await expectPrefilled('Dose (g)', '18');
        await expectPrefilled('Water (g)', '270');
        await expectPrefilled('Temperature (°C)', '93.5');
        await expectPrefilled('Minutes', '2');
        await expectPrefilled('Seconds', '30');
        await expectPrefilled('Beverage weight (g)', '36');
        await expectPrefilled('TDS (%)', '8.2');

        // The extraction yield follows the measured beverage and TDS.
        const expectedEy = 'EY: 16.4 %';
        await tester.scrollUntilVisible(
          find.text(expectedEy),
          240,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.text(expectedEy), findsOneWidget);

        final ratingCaption = find.descendant(
          of: find.byType(BrewForm),
          matching: find.text('Rating: 4.5 / 10'),
        );
        await tester.scrollUntilVisible(
          ratingCaption,
          240,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(ratingCaption, findsOneWidget);
        expect(
          tester
              .widget<Slider>(
                find.descendant(
                  of: find.byType(OptionalRatingSlider),
                  matching: find.byType(Slider),
                ),
              )
              .value,
          4.5,
        );
        await expectPrefilled('Notes', 'Sweet, clear finish');

        final dateChip = find.byKey(const ValueKey('brew-date-chip'));
        await tester.scrollUntilVisible(dateChip, -240, scrollable: scrollable);
        await tester.pumpAndSettle();
        final expectedDate = formatRegionalDate(
          brewedAt,
          tester.binding.platformDispatcher.locale,
        );
        expect(
          find.descendant(of: dateChip, matching: find.text(expectedDate)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('brew-time-chip')),
            matching: find.text(
              DateFormat.jm(tester.binding.platformDispatcher.locale.toString())
                  .format(brewedAt),
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(BrewForm), findsNothing);

        expect(await database.select(database.coffees).get(), beforeCoffees);
        expect(await database.select(database.coffeeLots).get(), beforeLots);
        expect(
          await database.select(database.coffeeComponents).get(),
          beforeComponents,
        );
        expect(await database.select(database.brews).get(), beforeBrews);
        expect(
          await database.select(database.brewMethods).get(),
          beforeMethods,
        );
        expect(await database.select(database.grinders).get(), beforeGrinders);
        expect(
          await database.select(database.methodTools).get(),
          beforeMethodTools,
        );
        expect(
          await database.select(database.brewToolSelections).get(),
          beforeBrewToolSelections,
        );
        expect(beforeBrews.single.id, brewId);

        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit').last);
        await tester.pumpAndSettle();

        final secondForm = find.byType(BrewForm);
        final secondScrollable = find
            .descendant(of: secondForm, matching: find.byType(Scrollable))
            .first;
        final grinderDropdown = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Grinder',
        );
        await tester.scrollUntilVisible(
          grinderDropdown,
          240,
          scrollable: secondScrollable,
        );
        await tester.ensureVisible(grinderDropdown);
        await tester.pumpAndSettle();
        await tester.tap(grinderDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not specified').last);
        await tester.pumpAndSettle();

        await repository.createGrinder(name: 'Fresh grinder');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(grinderDropdown)
              .initialValue,
          '',
          reason: 'catalog updates must not restore a grinder the user cleared',
        );

        final grindField = find.widgetWithText(TextFormField, 'Grind setting');
        await tester.scrollUntilVisible(
          grindField,
          240,
          scrollable: secondScrollable,
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(grindField).controller!.text,
          '24 clicks',
        );
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
        final savedBrew = await database.select(database.brews).getSingle();
        expect(savedBrew.isPreGround, isFalse);
        expect(savedBrew.grinderId, isNull);
        expect(savedBrew.grinderName, isNull);
        expect(savedBrew.grindSetting, '24 clicks');
        expect(savedBrew.timeSeconds, 150);
        expect(savedBrew.brewedAtMs, beforeBrews.single.brewedAtMs);

        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit').last);
        await tester.pumpAndSettle();
        final thirdForm = find.byType(BrewForm);
        final thirdScrollable = find
            .descendant(of: thirdForm, matching: find.byType(Scrollable))
            .first;
        final thirdGrinderDropdown = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Grinder',
        );
        await tester.scrollUntilVisible(
          thirdGrinderDropdown,
          240,
          scrollable: thirdScrollable,
        );
        await tester.ensureVisible(thirdGrinderDropdown);
        await tester.pumpAndSettle();
        await tester.tap(thirdGrinderDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pre-ground').last);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'Grind setting'),
          findsNothing,
        );
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
        final preGroundBrew = await database.select(database.brews).getSingle();
        expect(preGroundBrew.isPreGround, isTrue);
        expect(preGroundBrew.grinderId, isNull);
        expect(preGroundBrew.grinderName, isNull);
        expect(preGroundBrew.grindSetting, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
        await database.close();
      }
    },
  );

  testWidgets('repeat copies the recipe but starts with an empty result', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Repeat bean',
      roaster: 'Test roaster',
      initialGrams: 250,
    );
    final lot = (await repository.coffeeLots(coffeeId)).single;
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final grinderId = await repository.createGrinder(name: 'Comandante C40');
    final toolId = await repository.createMethodTool(
      methodId: methodId,
      name: 'Filter paper',
    );
    final originalAt = DateTime(2026, 9, 20, 10, 15);
    final originalId = await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodId: methodId,
      methodName: 'V60',
      grinderId: grinderId,
      grinderName: 'Comandante C40',
      grindSetting: '24 clicks',
      methodToolIds: [toolId],
      doseGrams: 18,
      waterGrams: 270,
      temperatureC: 93,
      beverageGrams: 250,
      timeSeconds: 155,
      tdsPercent: 1.35,
      rating: 8.5,
      notes: 'Sweet and clear',
      brewedAt: originalAt,
    );

    try {
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brews').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeat').last);
      await tester.pumpAndSettle();

      final form = find.byType(BrewForm);
      final scrollable = find
          .descendant(of: form, matching: find.byType(Scrollable))
          .first;
      final methodDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Choose a method',
      );
      final grinderDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Grinder',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(methodDropdown)
            .initialValue,
        methodId,
      );
      await tester.scrollUntilVisible(
        grinderDropdown,
        240,
        scrollable: scrollable,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(grinderDropdown)
            .initialValue,
        grinderId,
      );
      final toolChip = find.widgetWithText(FilterChip, 'Filter paper');
      await tester.scrollUntilVisible(toolChip, 240, scrollable: scrollable);
      expect(tester.widget<FilterChip>(toolChip).selected, isTrue);

      Future<TextFormField> repeatedField(String label) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.scrollUntilVisible(field, 240, scrollable: scrollable);
        await tester.pumpAndSettle();
        return tester.widget<TextFormField>(field);
      }

      expect(
        (await repeatedField('Grind setting')).controller!.text,
        '24 clicks',
      );
      expect((await repeatedField('Dose (g)')).controller!.text, '18');
      expect((await repeatedField('Water (g)')).controller!.text, '270');
      expect((await repeatedField('Temperature (°C)')).controller!.text, '93');

      final minutesField = await repeatedField('Minutes');
      expect(minutesField.controller!.text, isEmpty);
      expect(
        tester
            .widget<InputDecorator>(
              find.descendant(
                of: find.widgetWithText(TextFormField, 'Minutes'),
                matching: find.byType(InputDecorator),
              ),
            )
            .decoration
            .helperText,
        'Starting recipe: 2:35',
      );
      expect((await repeatedField('Seconds')).controller!.text, isEmpty);
      final yieldField = await repeatedField('Beverage weight (g)');
      expect(yieldField.controller!.text, isEmpty);
      final yieldDecorator = find.descendant(
        of: find.widgetWithText(TextFormField, 'Beverage weight (g)'),
        matching: find.byType(InputDecorator),
      );
      expect(
        tester.widget<InputDecorator>(yieldDecorator).decoration.helperText,
        'Starting recipe: 250 g',
      );
      expect((await repeatedField('TDS (%)')).controller!.text, isEmpty);
      expect(find.text('No rating'), findsOneWidget);
      expect(
        (await repeatedField('Notes')).controller!.text,
        'Sweet and clear',
      );

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final brews = await database.select(database.brews).get();
      expect(brews, hasLength(2));
      final repeated = brews.singleWhere((brew) => brew.id != originalId);
      expect(repeated.coffeeId, coffeeId);
      expect(repeated.lotId, lot.id);
      expect(repeated.methodId, methodId);
      expect(repeated.grinderId, grinderId);
      expect(repeated.grindSetting, '24 clicks');
      expect(repeated.doseGrams, 18);
      expect(repeated.waterGrams, 270);
      expect(repeated.temperatureC, 93);
      expect(repeated.beverageGrams, isNull);
      expect(repeated.timeSeconds, isNull);
      expect(repeated.tdsPercent, isNull);
      expect(repeated.rating, isNull);
      expect(repeated.notes, 'Sweet and clear');
      expect(
        repeated.brewedAtMs,
        greaterThan(originalAt.millisecondsSinceEpoch),
      );
      final original = brews.singleWhere((brew) => brew.id == originalId);
      expect(original.beverageGrams, 250);
      expect(original.timeSeconds, 155);
      expect(original.rating, 8.5);
      expect(original.notes, 'Sweet and clear');
      expect(
        (await repository.coffeeLots(coffeeId)).single.remainingGrams,
        214,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
      await database.close();
    }
  });
}
