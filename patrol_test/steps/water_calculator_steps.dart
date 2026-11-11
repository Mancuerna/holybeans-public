import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/water_alternatives_picker.dart';
import 'package:holybeans/ui/equipment/water_calculator_result.dart';
import 'package:holybeans/ui/equipment/water_chart.dart';
import 'package:holybeans/ui/equipment/water_profiles_page.dart';
import 'package:patrol/patrol.dart';

Future<void> checkWaterCalculator(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  final navigation = $.tester.getRect(find.byType(NavigationBar));
  await $.tester.tapAt(
    Offset(navigation.left + navigation.width * 3.5 / 4, navigation.center.dy),
  );
  await $.pumpAndSettle();
  await $.tester.ensureVisible(find.text('Water'));
  await $.pumpAndSettle();
  await $.tap(find.text('Water'));
  await $.tap(find.byKey(const ValueKey('open-water-calculator')));
  await $.enterText(find.byKey(const ValueKey('water-litres')), '5');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-preset')),
  );
  await $.tap(find.byKey(const ValueKey('water-preset')));
  await $.tap(find.text('Rao/Perger (Gagné 2018)').last);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-use-recipe-salts')),
  );
  await $.tap(find.byKey(const ValueKey('water-use-recipe-salts')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-calcium-form')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('water-calcium-form')));
  await $.tap(find.text('Anhydrous (CaCl₂)').last);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-dose-calciumChloride')),
  );
  expect(find.text('0.150 g'), findsOneWidget);
  await $.takeNativeScreenshot('water-rao-direct-doses');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-scatter-chart')),
  );
  await $.takeNativeScreenshot('water-target-result-chart');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-mode')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('water-mode')));
  await $.tap(find.text('Doses for a target').last);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-alternatives')),
  );
  await $.tap(find.text('Choose a salt combination'));
  final model = $.tester
      .widget<WaterAlternativesPicker>(find.byType(WaterAlternativesPicker))
      .model;
  final alternative = model.alternatives.indexWhere(
    (r) =>
        r.grams[WaterSalt.potassiumBicarbonate]! > 0 &&
        r.grams[WaterSalt.sodiumBicarbonate] == 0,
  );
  expect(alternative, greaterThanOrEqualTo(0));
  await $.scrollUntilVisible(
    finder: find.byKey(ValueKey('water-alternative-$alternative')),
  );
  await $.tap(find.byKey(ValueKey('water-alternative-$alternative')));
  expect(model.recipe!.grams[WaterSalt.sodiumBicarbonate], 0);
  expect(model.recipe!.result.kh, closeTo(40, .001));
  await $.takeNativeScreenshot('water-selected-alternative');

  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-target-gh-mode')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('water-target-gh-mode')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-mixture')),
  );
  await $.tap(find.byKey(const ValueKey('water-mixture')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-calcium-percent')),
  );
  await $.enterText(find.byKey(const ValueKey('water-calcium-percent')), '35');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-source-true-true')),
  );
  await $.tap(find.byKey(const ValueKey('water-source-true-true')));
  await $.tap(find.text('Magnesium chloride').last);
  await $.takeNativeScreenshot('water-mixture-controls');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-dose-calciumChloride')),
  );
  await $.takeNativeScreenshot('water-mixture-doses');
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.tap(find.text('Cancel').last);
  expect(await database.select(database.waterProfiles).get(), isEmpty);
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Profile name'),
    'Patrol Ca Mg mixture',
  );
  await $.tap(find.text('Save').last);
  var profiles = await database.select(database.waterProfiles).get();
  expect(profiles, hasLength(1));
  final recipe = WaterRecipe.fromJson(profiles.single.recipeJson!);
  expect(recipe.litres, 5);
  expect(recipe.calcium, CalciumForm.anhydrous);
  expect(recipe.calciumGhFraction, .35);
  expect(recipe.ghSource, WaterSalt.magnesiumChloride);
  expect(recipe.result.gh, closeTo(80, .001));
  expect(profiles.single.tdsPpm, isNull);
  expect(profiles.single.ph, isNull);
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('toggle-water-graph')));
  await $.tap(find.byKey(const ValueKey('toggle-water-graph')));
  await $.scrollUntilVisible(
    finder: find.byKey(ValueKey('water-point-${profiles.single.id}')),
  );
  await $.takeNativeScreenshot('water-saved-profile-chart');
  await $.tap(find.byKey(ValueKey('water-point-${profiles.single.id}')));
  await $.waitUntilVisible(find.text('Edit water profile'));
  await $.tap(find.text('Cancel').last);
  await $.tap(find.byKey(const ValueKey('toggle-water-graph')));
  await $.tap(find.byTooltip('Actions'));
  await $.tap(find.text('Open recipe'));
  expect(
    $.tester
        .widget<TextFormField>(find.byKey(const ValueKey('water-litres')))
        .controller!
        .text,
    '5',
  );
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-calcium-percent')),
  );
  expect(
    $.tester
        .widget<TextFormField>(
          find.byKey(const ValueKey('water-calcium-percent')),
        )
        .controller!
        .text,
    '35',
  );
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('open-water-calculator')));
  await $.tap(find.byKey(const ValueKey('open-water-calculator')));
  await $.tap(find.byKey(const ValueKey('water-mineral')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-base-more-ions')),
  );
  await $.tap(find.byKey(const ValueKey('water-base-more-ions')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-base-calcium')),
    scrollDirection: AxisDirection.up,
  );
  for (final (key, value) in [
    ('calcium', '10'),
    ('magnesium', '5'),
    ('bicarbonate', '150'),
  ]) {
    final field = find.byKey(ValueKey('water-base-$key'));
    await $.scrollUntilVisible(finder: field);
    await $.enterText(field, value);
  }
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-excess')),
  );
  await $.takeNativeScreenshot('water-bottle-excess-comparison');
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Profile name'),
    'Patrol mineral bottle',
  );
  await $.tap(find.text('Save').last);
  profiles = await database.select(database.waterProfiles).get();
  expect(profiles, hasLength(2));
  final bottle = profiles.singleWhere((p) => p.name == 'Patrol mineral bottle');
  expect(bottle.khPpmAsCaCO3, greaterThan(120));
  expect(bottle.sodiumPpm, isNull);
  expect(bottle.potassiumPpm, isNull);
  expect(
    WaterRecipe.fromJson(bottle.recipeJson!).grams.values.every((g) => g >= 0),
    isTrue,
  );
  expect(find.byType(WaterChart), findsOneWidget);

  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-litres')),
    scrollDirection: AxisDirection.up,
  );
  await $.enterText(find.byKey(const ValueKey('water-litres')), '6');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-add-salt')),
  );
  await $.tap(find.byKey(const ValueKey('water-add-salt')));
  await $.tap(find.text('Potassium bicarbonate').last);
  await $.scrollUntilVisible(finder: find.byKey(const ValueKey('water-mode')));
  await $.tap(find.byKey(const ValueKey('water-mode')));
  await $.tap(find.text('Result of my doses').last);
  final potassiumDose = find.byKey(
    const ValueKey('water-amount-potassiumBicarbonate'),
  );
  await $.scrollUntilVisible(finder: potassiumDose);
  await $.enterText(potassiumDose, '0,137');
  expect(
    $.tester.widget<TextFormField>(potassiumDose).controller!.text,
    fieldExact(.137),
  );
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-potassium-added')),
  );
  expect(find.textContaining('K added 8.92 mg/L'), findsOneWidget);
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Profile name'),
    'Patrol potassium bottle',
  );
  await $.tap(find.text('Save').last);
  profiles = await database.select(database.waterProfiles).get();
  final potassiumBottle = profiles.singleWhere(
    (p) => p.name == 'Patrol potassium bottle',
  );
  expect(potassiumBottle.potassiumPpm, isNull);
  expect(
    WaterRecipe.fromJson(potassiumBottle.recipeJson!)
        .grams[WaterSalt.potassiumBicarbonate],
    .137,
  );
  await $.platformAutomator.android.pressBack();
  await $.waitUntilVisible(find.byKey(const ValueKey('toggle-water-graph')));
  // The composition row itself, which can sit under the floating button
  // when only the name is in view.
  final composition = find.byKey(
    PageStorageKey('water-composition-${potassiumBottle.id}'),
  );
  await $.pumpAndSettle();
  final list = find
      .descendant(
        of: find.byType(WaterProfilesList),
        matching: find.byType(Scrollable),
      )
      .last;
  // The list keeps its previous offset; the new alphabetical row can be above it.
  await $.tester.drag(list, const Offset(0, 1500));
  await $.pumpAndSettle();
  await $.takeNativeScreenshot('water-returned-list');
  await $.scrollUntilVisible(finder: composition, view: list);
  await $.tap(composition);
  await $.pumpAndSettle();
  await $.scrollUntilVisible(
    finder: find.text('K added 8.92 mg/L'),
    view: list,
  );
  await $.takeNativeScreenshot('water-potassium-added-profile');
  await checkDirectIonTarget($, database);
}

Future<void> checkDirectIonTarget(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('open-water-calculator')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('open-water-calculator')));
  await $.scrollUntilVisible(finder: find.byKey(const ValueKey('water-mode')));
  await $.tap(find.byKey(const ValueKey('water-mode')));
  await $.tap(find.text('Doses for a target').last);
  expect(find.byKey(const ValueKey('water-alternatives')), findsNothing);

  for (final (key, value) in [
    ('kh', '30'),
    ('calcium', '20'),
    ('magnesium', '5'),
  ]) {
    await $.scrollUntilVisible(
      finder: find.byKey(ValueKey('water-target-$key')),
    );
    await $.enterText(find.byKey(ValueKey('water-target-$key')), value);
  }
  await $.takeNativeScreenshot('water-direct-ion-target');
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-remove-epsom')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('water-remove-epsom')));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-add-salt')),
  );
  await $.tap(find.byKey(const ValueKey('water-add-salt')));
  await $.tap(find.text('Magnesium chloride').last);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-dose-magnesiumChloride')),
  );
  await $.takeNativeScreenshot('water-direct-ion-result');
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Profile name'),
    'Patrol direct ions',
  );
  await $.tap(find.text('Save').last);
  final row = (await database.select(database.waterProfiles).get()).singleWhere(
    (p) => p.name == 'Patrol direct ions',
  );
  final recipe = WaterRecipe.fromJson(row.recipeJson!);
  expect(recipe.ionTargets, isTrue);
  expect(recipe.result[WaterIon.calcium], closeTo(20, .000001));
  expect(recipe.result[WaterIon.magnesium], closeTo(5, .000001));
  expect(recipe.result.kh, closeTo(30, .000001));
  expect(recipe.availableSalts, isNot(contains(WaterSalt.epsom)));
  expect(recipe.grams[WaterSalt.epsom], 0);
  await checkSavedWaterTarget($, database, row);
}

Future<void> checkSavedWaterTarget(
  PatrolIntegrationTester $,
  AppDatabase database,
  WaterProfile source,
) async {
  await $.platformAutomator.android.pressBack();
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('open-water-calculator')),
    scrollDirection: AxisDirection.up,
  );
  await $.tap(find.byKey(const ValueKey('open-water-calculator')));
  await $.enterText(find.byKey(const ValueKey('water-litres')), '3');
  await $.tap(find.byKey(const ValueKey('water-mineral')));
  for (final (key, value) in [
    ('kh', '10'),
    ('calcium', '5'),
    ('magnesium', '2'),
  ]) {
    await $.scrollUntilVisible(finder: find.byKey(ValueKey('water-base-$key')));
    await $.enterText(find.byKey(ValueKey('water-base-$key')), value);
  }
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-preset')),
  );
  await $.tap(find.byKey(const ValueKey('water-preset')));
  await $.scrollUntilVisible(
    finder: find.text(source.name),
    view: find.byType(Scrollable).last,
  );
  await $.takeNativeScreenshot('water-saved-target-menu');
  await $.tap(find.text(source.name).last);
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('water-dose-epsom')),
  );
  final result = $.tester
      .widget<WaterCalculatorResult>(find.byType(WaterCalculatorResult))
      .recipe;
  expect(result.litres, 3);
  expect(result.base[WaterIon.calcium], 5);
  expect(result.result[WaterIon.calcium], closeTo(20, .001));
  expect(result.result[WaterIon.magnesium], closeTo(5, .001));
  expect(result.result.kh, closeTo(30, .001));
  expect(result.grams[WaterSalt.epsom], greaterThan(0));
  expect(result.grams[WaterSalt.magnesiumChloride], 0);
  await $.takeNativeScreenshot('water-saved-target-result');
  await $.tap(find.byKey(const ValueKey('water-save-result')));
  await $.enterText(
    find.widgetWithText(TextFormField, 'Profile name'),
    'Patrol saved target',
  );
  await $.tap(find.text('Save').last);
  final rows = await database.select(database.waterProfiles).get();
  expect(rows.singleWhere((p) => p.id == source.id), source);
  final saved = WaterRecipe.fromJson(
    rows.singleWhere((p) => p.name == 'Patrol saved target').recipeJson!,
  );
  expect(saved.target!.toMap(), result.target!.toMap());
  expect(saved.presetId, isNull);
}
