import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

void main() {
  testWidgets(
    'ratio targets change water but preserve the measured espresso yield',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      tester.view.physicalSize = const Size(480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Ratio shortcut coffee',
        roaster: 'Test roaster',
      );
      final espressoId = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
      final filterId = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodId: filterId,
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 270,
        beverageGrams: 220,
        timeSeconds: 155,
        temperatureC: 93,
        tdsPercent: 8.2,
        notes: 'Keep these results',
      );
      final brew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingle();
      final coffees = await database.select(database.coffees).get();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BrewForm(
                      repository: repository,
                      settings: BrewParameterSettings(repository.database),
                      coffees: coffees,
                      existing: brew,
                    ),
                  ),
                  child: const Text('Open brew editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open brew editor'));
      await tester.pumpAndSettle();

      final form = find.byType(BrewForm);
      final scrollable = find
          .descendant(of: form, matching: find.byType(Scrollable))
          .first;

      Future<void> scrollToStart() async {
        var position = tester.state<ScrollableState>(scrollable).position;
        while (position.pixels > position.minScrollExtent) {
          await tester.drag(scrollable, const Offset(0, 500));
          await tester.pumpAndSettle();
          position = tester.state<ScrollableState>(scrollable).position;
        }
      }

      Future<void> selectMethod(String name) async {
        await scrollToStart();
        final methodField = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Choose a method',
        );
        await tester.scrollUntilVisible(
          methodField,
          220,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(methodField);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Future<void> chooseRatio(double ratio) async {
        final slider = find.byKey(const ValueKey('brew-ratio-slider'));
        await scrollToStart();
        await tester.scrollUntilVisible(slider, 220, scrollable: scrollable);
        await tester.pumpAndSettle();
        tester.widget<Slider>(slider).onChanged!(ratio);
        await tester.pumpAndSettle();
      }

      Future<String> fieldValue(String label) async {
        await scrollToStart();
        final field = find.widgetWithText(TextFormField, label);
        await tester.scrollUntilVisible(field, 220, scrollable: scrollable);
        await tester.pumpAndSettle();
        return tester.widget<TextFormField>(field).controller!.text;
      }

      // In the fields; the recipe header above them shows it too.
      expect(
        find.descendant(
          of: find.byType(Form),
          matching: find.text('Ratio: 1:15'),
        ),
        findsOneWidget,
      );
      expect(await fieldValue('Water (g)'), '270');
      expect(await fieldValue('Beverage weight (g)'), '220');
      await chooseRatio(16);
      expect(await fieldValue('Water (g)'), '288');
      expect(await fieldValue('Beverage weight (g)'), '220');

      // Espresso sets only the dose; the yield, a result, stays.
      await selectMethod('Espresso');
      await chooseRatio(2.3);
      expect(find.text('Target beverage: 41.4 g'), findsOneWidget);
      await fieldValue('Dose (g)');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose (g)'),
        '17',
      );
      await tester.pumpAndSettle();
      expect(find.text('Target beverage: 39.1 g'), findsOneWidget);
      expect(find.text('1:16'), findsNothing);
      expect(await fieldValue('Beverage weight (g)'), '220');
      expect(await fieldValue('TDS (%)'), '8.2');
      expect(find.widgetWithText(TextFormField, 'Water (g)'), findsNothing);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final saved = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingle();
      expect(saved.methodId, espressoId);
      expect(saved.waterGrams, isNull);
      expect(saved.beverageGrams, 220);
      expect(saved.tdsPercent, 8.2);
      expect(saved.temperatureC, 93);
      expect(saved.timeSeconds, 155);
      expect(saved.notes, 'Keep these results');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('an untouched ratio outside the usual range keeps its water', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Coarse filter',
      roaster: 'Test roaster',
    );
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'V60',
      doseGrams: 18,
      waterGrams: 396,
    );
    final brew = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();
    final coffees = await database.select(database.coffees).get();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
    final slider = find.byKey(const ValueKey('brew-ratio-slider'));
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(slider, 200, scrollable: scrollable);
    expect(tester.widget<Slider>(slider).value, 20);
    expect(tester.widget<Slider>(slider).onChanged, isNull);

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final saved = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();
    expect(saved.waterGrams, 396);
    expect(saved.doseGrams, 18);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
