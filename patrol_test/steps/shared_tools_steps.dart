import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

Future<void> checkSharedTools(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repo = JournalRepository(database);
  final coffee = await repo.createCoffee(
    name: 'Patrol tools',
    roaster: 'Fixture',
    initialGrams: 250,
  );
  final v60 = await repo.createMethod(name: 'V60', category: 'pourover');
  final origami = await repo.createMethod(
    name: 'Origami',
    category: 'pourover',
  );
  final oldTool = await repo.createMethodTool(
    methodId: origami,
    name: 'Abaca antiguo',
  );
  final archivedBrew = await repo.createBrew(
    coffeeId: coffee,
    methodId: origami,
    methodName: 'Origami',
    methodToolIds: [oldTool],
    doseGrams: 15,
  );
  await repo.setBrewArchived(archivedBrew, archived: true);
  final originalSelections = await database
      .select(database.brewToolSelections)
      .get();

  Future<void> tab(String label) => $.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  Future<void> toolTab() async {
    await tab('Equipment');
    await $.tap(find.text('Accessories').first);
  }

  Future<void> menu(String id) => $.tap(
    find.descendant(
      of: find.byKey(ValueKey('tool-card-$id')),
      matching: find.byTooltip('Actions'),
    ),
  );
  // Drags on the phone fling past a field, so the form centres it instead.
  Future<void> showBrewField(Finder field) async {
    await Scrollable.ensureVisible($.tester.element(field), alignment: 0.5);
    await $.pumpAndSettle();
  }

  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('en'),
    ),
  );
  await toolTab();
  await $.tap(find.text('Add accessory'));
  await $.enterText(find.byKey(const ValueKey('tool-name')), 'Cafec Abaca');
  await $.tap(find.byKey(ValueKey('tool-method-$v60')));
  await $.tap(find.text('Save').last);
  var catalog = await repo.toolCatalog();
  final shared = catalog
      .visible()
      .singleWhere((tool) => tool.name == 'Cafec Abaca')
      .id;
  expect(catalog.methodsByTool[shared], {v60});

  await $.tap(find.text('Methods').first);
  await $.tap(
    find.descendant(
      of: find.byKey(ValueKey('method-card-$origami')),
      matching: find.byTooltip('Actions'),
    ),
  );
  await $.tap(find.text('Manage accessories'));
  await $.tap(find.byTooltip('Add accessory'));
  final name = find.byKey(const ValueKey('tool-name'));
  await $.tap(name);
  await $.tester.enterText(name, 'Cafe');
  await $.tester.pumpAndSettle();
  await $.waitUntilVisible(find.byKey(ValueKey('tool-suggestion-$shared')));
  await $.takeNativeScreenshot('shared-tool-autocomplete');
  await $.tap(find.byKey(ValueKey('tool-suggestion-$shared')));
  await $.tap(find.text('Save').last);
  await $.tap(find.byTooltip('Cancel'));
  catalog = await repo.toolCatalog();
  expect(catalog.methodsByTool[shared], {v60, origami});
  expect(catalog.visible(), hasLength(2));

  await tab('Home');
  await $.tap(find.text('Brew'));
  final beanChoice = find.byKey(const ValueKey('brew-coffee-picker'));
  await $.tap(beanChoice);
  await $.tap(find.text('Patrol tools').last);
  final methodChoice = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.decoration.labelText == 'Choose a method',
  );
  await $.tap(methodChoice);
  await $.tap(find.text('V60').last);
  final chip = find.widgetWithText(FilterChip, 'Cafec Abaca');
  await showBrewField(chip);
  await $.tap(chip);
  expect($.tester.widget<FilterChip>(chip).selected, isTrue);
  await $.takeNativeScreenshot('shared-tool-brew-chip');
  for (final (label, value) in [
    ('Dose (g)', '15'),
    ('Water (g)', '250'),
    ('Minutes', '3'),
  ]) {
    final field = find.widgetWithText(TextFormField, label);
    await showBrewField(field);
    await $.enterText(field, value);
  }
  await $.tap(find.text('Save').last);
  final active = (await database.select(database.brews).get()).singleWhere(
    (brew) => brew.archivedAtMs == null,
  );
  expect(await repo.brewToolIds(active.id), [shared]);
  expect((await repo.toolCatalog()).useCounts[shared], 1);

  await toolTab();
  await menu(oldTool);
  await $.tap(find.text('Merge accessories'));
  await $.tap(find.byKey(const ValueKey('merge-tool-target')));
  await $.tap(find.textContaining('Cafec Abaca,').last);
  await $.tap(find.widgetWithText(FilledButton, 'Merge accessories'));
  catalog = await repo.toolCatalog();
  expect(catalog.visible().single.id, shared);
  expect(catalog.useCounts[shared], 2);
  expect(
    await database.select(database.brewToolSelections).get(),
    containsAll(originalSelections),
  );
  expect(await repo.brewToolIds(archivedBrew), [shared]);
  await $.takeNativeScreenshot('shared-tools-catalog');

  await $.tap(find.text('Cafec Abaca').first);
  await $.enterText(find.byKey(const ValueKey('tool-name')), 'Cafec Abaca 02');
  await $.tap(find.byKey(ValueKey('tool-method-$origami')));
  await $.tap(find.text('Save').last);
  expect((await repo.toolCatalog()).methodsByTool[shared], {v60});
  expect(await repo.brewToolIds(archivedBrew), [shared]);
  await menu(shared);
  await $.tap(find.text('Archive accessory'));
  expect((await repo.toolCatalog()).visible(), isEmpty);

  await tab('Brews');
  final brewCard = find.byKey(ValueKey('brew-card-${active.id}'));
  await $.tap(
    find.descendant(of: brewCard, matching: find.byTooltip('Actions')),
  );
  await $.tap(find.text('Edit').last);
  final archivedChip = find.widgetWithText(FilterChip, 'Cafec Abaca 02');
  await showBrewField(archivedChip);
  expect($.tester.widget<FilterChip>(archivedChip).selected, isTrue);
  expect(
    find.descendant(of: archivedChip, matching: find.text('2')),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('shared-tool-archived-edit');
  await $.tap(find.text('Save').last);
  expect(await repo.brewToolIds(active.id), [shared]);
  expect((await repo.coffeeLots(coffee)).single.remainingGrams, 235);

  // Review the same catalog in Spanish and restore the archived shared tool.
  await $.pumpWidgetAndSettle(const SizedBox.shrink());
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(database: database),
      initialLocale: const Locale('es'),
    ),
  );
  await tab('Equipo');
  await $.tap(find.text('Accesorios').first);
  await $.tap(find.byKey(const ValueKey('equipment-show-archived')));
  await $.tap(
    find.descendant(
      of: find.byKey(ValueKey('tool-card-$shared')),
      matching: find.byTooltip('Acciones'),
    ),
  );
  await $.tap(find.text('Restaurar accesorio'));
  await $.takeNativeScreenshot('shared-tools-catalog-es');
  expect((await repo.toolCatalog()).visible().single.id, shared);
  expect((await repo.toolCatalog()).useCounts[shared], 2);
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
}
