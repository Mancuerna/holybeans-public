import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_calculator_page.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';
import 'package:holybeans/ui/equipment/water_chart.dart';
import 'package:holybeans/ui/equipment/water_profiles_page.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = JournalRepository(db);
  });
  tearDown(() async {
    await db.close();
  });

  for (final locale in ['en', 'es']) {
    testWidgets('mixture controls save and reopen in $locale', (tester) async {
      await tester.pumpWidget(
        _harness(WaterCalculatorPage(repository: repo), locale: Locale(locale)),
      );
      await tester.pumpAndSettle();
      final strings = await AppLocalizations.delegate.load(Locale(locale));
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('water-calculator-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> reveal(String key, [double delta = 160]) async {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          delta,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
      }

      await reveal('water-mode');
      await tester.tap(find.byKey(const ValueKey('water-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.waterCustomMode).last);
      await tester.pumpAndSettle();
      await reveal('water-target-gh-mode');
      await tester.tap(find.byKey(const ValueKey('water-target-gh-mode')));
      await tester.pumpAndSettle();
      await reveal('water-mixture');
      await tester.tap(find.byKey(const ValueKey('water-mixture')));
      await tester.pumpAndSettle();
      await reveal('water-calcium-percent');
      await tester.enterText(
        find.byKey(const ValueKey('water-calcium-percent')),
        '35',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await reveal('water-calcium-form', -160);
      await tester.tap(find.byKey(const ValueKey('water-calcium-form')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.waterCalciumAnhydrous).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('water-save-result')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, strings.waterProfileName),
        'Mixed water',
      );
      await tester.tap(find.text(strings.save).last);
      await tester.pumpAndSettle();
      final row = await db.select(db.waterProfiles).getSingle();
      final recipe = WaterRecipe.fromJson(row.recipeJson!);
      expect(recipe.calciumGhFraction, .35);
      expect(recipe.calcium, CalciumForm.anhydrous);
      expect(recipe.result.gh, closeTo(80, 1e-8));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _harness(
          WaterCalculatorPage(repository: repo, seed: recipe),
          locale: Locale(locale),
        ),
      );
      await tester.pumpAndSettle();
      await reveal('water-calcium-percent');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('water-calcium-percent')),
            )
            .controller!
            .text,
        '35',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'preset scales, cancel writes nothing, save keeps recipe and manual edits detach it',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(WaterCalculatorPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('water-litres')), '5');
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('water-calculator-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final dose = find.byKey(const ValueKey('water-dose-epsom'));
      await tester.scrollUntilVisible(dose, 180, scrollable: scroll);
      expect(tester.widget<Text>(dose).data, '0.985 g');
      await tester.tap(find.byKey(const ValueKey('water-save-result')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(await db.select(db.waterProfiles).get(), isEmpty);
      await tester.tap(find.byKey(const ValueKey('water-save-result')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Profile name'),
        'Five litres BH',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      var profile = (await db.select(db.waterProfiles).get()).single;
      expect(profile.recipeJson, isNotNull);
      expect(profile.bicarbonatePpm, closeTo(48.77, .01));
      expect(profile.tdsPpm, isNull);
      expect(profile.ph, isNull);
      final recipe = WaterRecipe.fromJson(profile.recipeJson!);
      expect(recipe.litres, 5);
      expect(recipe.grams[WaterSalt.epsom], closeTo(.9850240141, 1e-9));
      final originalBicarbonate = profile.bicarbonatePpm;
      await tester.pumpWidget(
        _harness(
          Scaffold(
            body: WaterProfilesList(repository: repo, showArchived: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Five litres BH'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
            )
            .controller!
            .text,
        '80',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(
                TextFormField,
                'KH alkalinity (ppm as CaCO₃)',
              ),
            )
            .controller!
            .text,
        '40',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Profile name'),
        'Renamed BH',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      profile = (await db.select(db.waterProfiles).get()).single;
      expect(profile.recipeJson, isNotNull);
      expect(profile.bicarbonatePpm, originalBicarbonate);
      await tester.tap(find.text('Renamed BH'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
        '',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'KH alkalinity (ppm as CaCO₃)'),
        '',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      profile = (await db.select(db.waterProfiles).get()).single;
      expect(profile.ghPpmAsCaCO3, isNull);
      expect(profile.khPpmAsCaCO3, isNull);
      expect(profile.bicarbonatePpm, originalBicarbonate);
      expect(profile.recipeJson, isNotNull);
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Open recipe'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renamed BH'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
        '90',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(
        (await db.select(db.waterProfiles).get()).single.recipeJson,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('water editor hides floating-point noise', (tester) async {
    await repo.createWaterProfile(
      name: 'Floating point',
      ghPpmAsCaCO3: 80.00000000000001,
      khPpmAsCaCO3: 39.99999999999999,
    );
    await tester.pumpWidget(
      _harness(
        Scaffold(
          body: WaterProfilesList(repository: repo, showArchived: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floating point'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
          )
          .controller!
          .text,
      '80',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'KH alkalinity (ppm as CaCO₃)'),
          )
          .controller!
          .text,
      '40',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'bottle blanks stay unknown, excess is visible and invalid values block saving',
    (tester) async {
      await tester.pumpWidget(_harness(WaterCalculatorPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('water-mineral')));
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('water-calculator-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> fill(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          field,
          key == 'water-litres' ? -120 : 120,
          scrollable: scroll,
        );
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      await fill('water-base-calcium', '10');
      await fill('water-base-magnesium', '5');
      final extra = find.byKey(const ValueKey('water-base-more-ions'));
      await tester.scrollUntilVisible(extra, 120, scrollable: scroll);
      await tester.tap(extra);
      await tester.pumpAndSettle();
      await fill('water-base-bicarbonate', '150');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('water-excess')),
        170,
        scrollable: scroll,
      );
      expect(find.byKey(const ValueKey('water-excess')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('water-save-result')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Profile name'),
        'Bottle adjusted',
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final profile = (await db.select(db.waterProfiles).get()).single;
      expect(profile.sodiumPpm, isNull);
      expect(profile.potassiumPpm, isNull);
      expect(profile.calciumPpm, greaterThanOrEqualTo(10));
      expect(profile.khPpmAsCaCO3, greaterThan(120));
      await fill('water-litres', '0');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('water-save-result')),
            )
            .onPressed,
        isNull,
      );
      await fill('water-litres', 'NaN');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('water-save-result')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'saved bottle recipe shows added potassium while total stays unknown',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'es',
        'ES',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      final recipe = WaterRecipe(
        litres: 6,
        calcium: CalciumForm.anhydrous,
        mode: WaterCalculationMode.quantities,
        base: WaterComposition(
          ions: {
            WaterIon.calcium: 3,
            WaterIon.magnesium: 3.2,
            WaterIon.sodium: 5.3,
            WaterIon.chloride: 7.8,
            WaterIon.sulfate: 3,
            WaterIon.bicarbonate: 21,
          },
        ),
        grams: {WaterSalt.potassiumBicarbonate: .1717434618447803},
      );
      expect(recipe.result[WaterIon.potassium], isNull);
      expect(recipe.added[WaterIon.potassium], closeTo(11.18, .01));
      await repo.createWaterProfile(
        name: 'Rao/Perger Encinas',
        ghPpmAsCaCO3: recipe.result.gh,
        khPpmAsCaCO3: recipe.result.kh,
        minerals: WaterMinerals(
          calcium: recipe.result[WaterIon.calcium],
          magnesium: recipe.result[WaterIon.magnesium],
          bicarbonate: recipe.result[WaterIon.bicarbonate],
        ),
        recipeJson: recipe.toJson(),
      );
      await tester.pumpWidget(
        _harness(
          Scaffold(
            body: WaterProfilesList(repository: repo, showArchived: false),
          ),
          locale: const Locale('es'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('K añadido 11,18 mg/L'), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('K añadido 11,18 mg/L'), findsOneWidget);
      expect(
        (await db.select(db.waterProfiles).getSingle()).potassiumPpm,
        isNull,
      );

      await tester.pumpWidget(
        _harness(
          Scaffold(
            body: ListView(children: [WaterCalculatorResult(recipe: recipe)]),
          ),
          locale: const Locale('es'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('water-potassium-added')))
            .data,
        contains('K añadido 11,18 mg/L'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chart keeps missing coordinates out and coincident waters selectable',
    (tester) async {
      await repo.createWaterProfile(
        name: 'A',
        ghPpmAsCaCO3: 80,
        khPpmAsCaCO3: 40,
      );
      await repo.createWaterProfile(
        name: 'B',
        ghPpmAsCaCO3: 80,
        khPpmAsCaCO3: 40,
      );
      await repo.createWaterProfile(name: 'Unknown water');
      await tester.pumpWidget(
        _harness(
          Scaffold(
            body: WaterProfilesList(repository: repo, showArchived: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-water-graph')));
      await tester.pumpAndSettle();
      final chart = tester.widget<WaterChart>(find.byType(WaterChart));
      expect(
        chart.points.where((p) => p.hasCoordinates),
        hasLength(WaterPreset.values.length + 2),
      );
      expect(
        chart.points.where((p) => !p.hasCoordinates).single.label,
        'Unknown water',
      );
      final painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('water-scatter-chart')),
          )
          .painter!;
      expect(painter, isNotNull);
      final a = (await db.select(db.waterProfiles).get()).singleWhere(
        (p) => p.name == 'A',
      );
      final button = find.byKey(ValueKey('water-point-${a.id}'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Edit water profile'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Profile name'),
            )
            .controller!
            .text,
        'A',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'Spanish calculator stays readable with large text and a narrow screen',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'es',
        'ES',
      );
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _harness(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.5),
            ),
            child: WaterCalculatorPage(repository: repo),
          ),
          locale: const Locale('es'),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('water-calculator-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(WaterChart),
        180,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Guardar como perfil de agua'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('water-dose-epsom')))
            .data,
        '0,197 g',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}

Widget _harness(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    );
