import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('water profile catalog supports create, edit, archive, restore', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    _setNarrowScreen(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final navigation = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(
        navigation.left + navigation.width * 3.5 / 4,
        navigation.center.dy,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add water profile'));
    await tester.pumpAndSettle();

    final nameField = find.widgetWithText(TextFormField, 'Profile name');
    await tester.enterText(nameField, 'Tap water');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final tdsField = find.widgetWithText(TextFormField, 'Water TDS (ppm)');
    final formList = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(tdsField, 160, scrollable: formList);
    // Fields further down are built as the form scrolls.
    Future<void> fill(Finder field, String text) async {
      await tester.scrollUntilVisible(field, 120, scrollable: formList);
      await tester.enterText(field, text);
    }

    await fill(
      find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
      '60',
    );
    await fill(
      find.widgetWithText(TextFormField, 'KH alkalinity (ppm as CaCO₃)'),
      '35',
    );
    await fill(tdsField, '95.35');
    await fill(find.widgetWithText(TextFormField, 'pH (0–14)'), '7.2');
    await fill(
      find.widgetWithText(TextFormField, 'Notes (optional)'),
      'Carbon filtered',
    );
    expect(tester.getRect(tdsField).bottom, lessThan(500));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text('Tap water'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('95.35'), findsOneWidget);
    expect(find.text('Carbon filtered'), findsOneWidget);

    await tester.tap(find.text('Tap water'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Water TDS (ppm)'),
          )
          .controller!
          .text,
      '95.35',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Profile name'),
      'Filtered tap',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Filtered tap'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Actions'));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive water profile'));
    await tester.pumpAndSettle();
    expect(find.text('No active water profiles yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('equipment-show-archived')));
    await tester.pumpAndSettle();
    expect(find.text('Filtered tap'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Actions'));
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore water profile'));
    await tester.pumpAndSettle();
    expect(find.text('Filtered tap'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a brew can create and save an in-place water profile', (
    tester,
  ) async {
    final database = memoryDatabase();
    final repository = JournalRepository(database);
    addTearDown(database.close);
    _setNarrowScreen(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coffeeId = await repository.createCoffee(
      name: 'Water brew bean',
      roaster: 'Test roaster',
    );
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(coffeeId))).getSingle();
    await repository.createMethod(name: 'V60', category: 'pourover');

    await tester.pumpWidget(_brewHarness(repository, coffee));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-brew-form')));
    await tester.pumpAndSettle();

    final methodSelector = _waterSelector('Choose a method');
    await tester.tap(methodSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('V60').last);
    await tester.pumpAndSettle();

    final form = find.byType(BrewForm);
    final scrollable = find
        .descendant(of: form, matching: find.byType(Scrollable))
        .first;
    final selector = _waterSelector('Water profile (optional)');
    await tester.scrollUntilVisible(selector, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add water profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Profile name'),
      'Recipe water',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'GH hardness (ppm as CaCO₃)'),
      '55',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final profile = await database.select(database.waterProfiles).getSingle();
    final profileId = profile.id;
    expect(
      tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
      profileId,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final savedBrew = await database.select(database.brews).getSingle();
    expect(savedBrew.waterProfileId, profileId);
    expect(savedBrew.waterProfileName, 'Recipe water');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'repeat shows archived water as a reference without selecting it',
    (tester) async {
      final database = memoryDatabase();
      final repository = JournalRepository(database);
      addTearDown(database.close);
      _setNarrowScreen(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final coffeeId = await repository.createCoffee(
        name: 'Archived water bean',
        roaster: 'Test roaster',
      );
      final coffee = await (database.select(
        database.coffees,
      )..where((row) => row.id.equals(coffeeId))).getSingle();
      await repository.createMethod(name: 'V60', category: 'pourover');
      final profileId = await repository.createWaterProfile(name: 'Old recipe');
      final originalId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        waterProfileId: profileId,
      );
      await repository.setWaterProfileArchived(profileId, archived: true);
      final original = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(originalId))).getSingle();

      await tester.pumpWidget(
        _brewHarness(repository, coffee, seed: original, repeat: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-brew-form')));
      await tester.pumpAndSettle();

      final selector = _waterSelector('Water profile (optional)');
      final form = find.byType(BrewForm);
      final scrollable = find
          .descendant(of: form, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(selector, 180, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
        '',
      );
      expect(
        find.text('Previous brew used archived water: Old recipe'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final brews = await database.select(database.brews).get();
      expect(brews, hasLength(2));
      final repeated = brews.singleWhere((brew) => brew.id != originalId);
      expect(repeated.waterProfileId, isNull);
      expect(repeated.waterProfileName, isNull);
      expect(
        brews.singleWhere((brew) => brew.id == originalId).waterProfileName,
        'Old recipe',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets('repeat can replace archived water with a new active profile', (
    tester,
  ) async {
    final database = memoryDatabase();
    final repository = JournalRepository(database);
    addTearDown(database.close);
    _setNarrowScreen(tester);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coffeeId = await repository.createCoffee(
      name: 'Replacement water bean',
      roaster: 'Test roaster',
    );
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(coffeeId))).getSingle();
    await repository.createMethod(name: 'V60', category: 'pourover');
    final archivedId = await repository.createWaterProfile(
      name: 'Archived recipe',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      waterProfileId: archivedId,
    );
    await repository.setWaterProfileArchived(archivedId, archived: true);
    final seed = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();

    await tester.pumpWidget(
      _brewHarness(repository, coffee, seed: seed, repeat: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-brew-form')));
    await tester.pumpAndSettle();

    final selector = _waterSelector('Water profile (optional)');
    final scrollable = find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(selector, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add water profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Profile name'),
      'Current recipe',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final profiles = await database.select(database.waterProfiles).get();
    final current = profiles.singleWhere((profile) => profile.id != archivedId);
    expect(
      tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
      current.id,
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final brews = await database.select(database.brews).get();
    final repeated = brews.singleWhere((brew) => brew.id != brewId);
    expect(repeated.waterProfileId, current.id);
    expect(repeated.waterProfileName, 'Current recipe');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

Widget _brewHarness(
  JournalRepository repository,
  Coffee coffee, {
  Brew? seed,
  bool repeat = false,
}) => localizedApp(
  locale: const Locale('en'),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: IconButton(
          key: const ValueKey('open-brew-form'),
          icon: const Icon(Icons.add),
          onPressed: () => showModalBottomSheet<BrewFormResult>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => BrewForm(
              repository: repository,
              settings: BrewParameterSettings(repository.database),
              coffees: [coffee],
              seed: seed,
              repeat: repeat,
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder _waterSelector(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label,
);

void _setNarrowScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
}
