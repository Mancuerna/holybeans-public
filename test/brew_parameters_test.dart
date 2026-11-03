import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations_en.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/ui_test_support.dart';

void main() {
  test('the essentials preset only hides what can be hidden', () {
    expect(
      essentialHiddenParameters.every(
        (parameter) => parameter.canHide && parameter.isBrewField,
      ),
      isTrue,
    );
    // The recipe and its result stay in sight.
    for (final kept in [
      BrewParameter.water,
      BrewParameter.beverage,
      BrewParameter.ratio,
      BrewParameter.grindSetting,
      BrewParameter.rating,
    ]) {
      expect(essentialHiddenParameters, isNot(contains(kept)));
    }
  });

  setUpAll(() => initializeDateFormatting('en'));

  group('stored choices', () {
    test('earlier hidden names keep their meaning', () {
      expect(
        decodeHiddenParameters([
          'waterProfile',
          'temperature',
          'grindRpm',
          'pressure',
          'preinfusion',
          'bloom',
          'firstDrip',
          'tds',
          'dose',
          'unknown',
        ]),
        {
          BrewParameter.waterProfile,
          BrewParameter.temperature,
          BrewParameter.grindRpm,
          BrewParameter.pressure,
          BrewParameter.preinfusion,
          BrewParameter.bloom,
          BrewParameter.firstDrip,
          BrewParameter.tds,
        },
      );
    });

    test('an earlier share list gains the new parameters once', () {
      final legacy = decodeSharedParameters(['coffee', 'dose', 'notes']);
      expect(legacy, {
        BrewParameter.coffee,
        BrewParameter.dose,
        BrewParameter.notes,
        ...newlySharedParameters,
      });
      // Saved again with the marker, an unchecked new one stays unchecked.
      final saved = encodeSharedParameters(
        {...legacy}..remove(BrewParameter.ratio),
      );
      expect(saved.first, sharedParametersMarker);
      expect(
        decodeSharedParameters(saved),
        isNot(contains(BrewParameter.ratio)),
      );
      expect(decodeSharedParameters([]), defaultSharedParameters);
      expect(
        defaultSharedParameters,
        containsAll([BrewParameter.ratio, BrewParameter.grindSetting]),
      );
      for (final personal in [
        BrewParameter.date,
        BrewParameter.rating,
        BrewParameter.notes,
      ]) {
        expect(defaultSharedParameters, isNot(contains(personal)));
      }
      expect(defaultSharedParameters, isNot(contains(BrewParameter.photos)));
    });

    test('settings keep both lists in the preferences row', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final settings = BrewParameterSettings(database);
      expect(await settings.loadHidden(), isEmpty);
      expect(await settings.loadShared(), defaultSharedParameters);
      await settings.saveHidden({BrewParameter.tools, BrewParameter.dose});
      await settings.saveShared({BrewParameter.ratio});
      expect(await settings.loadHidden(), {BrewParameter.tools});
      expect(await settings.loadShared(), {BrewParameter.ratio});
      await expectLater(settings.saveShared({}), throwsArgumentError);
      // A row written by an earlier version (no marker) still reads.
      await database.customStatement(
        'UPDATE app_preferences SET share_fields_json = ?',
        [
          jsonEncode(['coffee']),
        ],
      );
      expect(await settings.loadShared(), {
        BrewParameter.coffee,
        ...newlySharedParameters,
      });
    });
  });

  test('the shared text includes ratio, grinding and espresso times', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    final method = await repository.createMethod(
      name: 'Linea',
      category: 'espresso',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'Linea',
      methodId: method,
      grinderName: 'Lagom',
      grindSetting: '1.1',
      grindRpm: 6,
      doseGrams: 17,
      beverageGrams: 42,
      timeSeconds: 34,
      preinfusionSeconds: 8,
      firstDripSeconds: 4,
      pressureBar: 7.1,
      profileName: 'Linea Mini',
    );
    // RPM only applies with an adjustable grinder; set it directly.
    await database.customStatement('UPDATE brews SET grind_rpm = 6');
    final brew = (await database.select(database.brews).get()).singleWhere(
      (row) => row.id == brewId,
    );
    final text = BrewShareText.build(
      strings: AppLocalizationsEn(),
      coffee: await repository.coffee(coffeeId).then((value) => value!),
      components: const [],
      brew: brew,
      method: (await database.select(database.brewMethods).get()).single,
      toolNames: const ['Puck screen'],
      fields: BrewParameter.values.toSet(),
    );
    expect(
      text.split('\n').skipWhile((line) => !line.startsWith('Dose')).toList(),
      [
        'Dose: 17 g',
        'Beverage weight: 42 g',
        'Ratio: 1:2.5',
        'Grinder: Lagom',
        'Grind setting: 1.1',
        'RPM: 6',
        'Accessories: Puck screen',
        'Profile: Linea Mini',
        'Extraction time: 0:34',
        'Pre-infusion: 8 s',
        'First drip: 4 s',
        'Peak pressure: 7.1 bar',
      ],
    );
  });

  group('hidden parameters', () {
    Future<(AppDatabase, JournalRepository)> journal() async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Hidden coffee',
        roaster: 'R',
      );
      final method = await repository.createMethod(
        name: 'Linea',
        category: 'espresso',
      );
      await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Linea',
        methodId: method,
        doseGrams: 17,
        beverageGrams: 42,
        timeSeconds: 34,
        firstDripSeconds: 4,
        notes: 'Secret note',
      );
      await BrewParameterSettings(database)
          .saveHidden({BrewParameter.firstDrip, BrewParameter.notes});
      return (database, repository);
    }

    Future<void> stop(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('details hide them until revealed', (tester) async {
      final (database, _) = await journal();
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 2);
      expect(find.textContaining('Secret note'), findsNothing);
      await tester.tap(find.text('Hidden coffee').first);
      await tester.pumpAndSettle();
      expect(find.text('First drip'), findsNothing);
      expect(find.text('Secret note'), findsNothing);
      expect(find.text('2 hidden values, Show'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('brew-detail-hidden')));
      await tester.pumpAndSettle();
      expect(find.text('First drip'), findsOneWidget);
      expect(find.text('Secret note'), findsOneWidget);
      expect(find.text('2 hidden values, Hide'), findsOneWidget);
      await stop(tester);
    });

    testWidgets('editing keeps hidden values that the form does not show', (
      tester,
    ) async {
      final (database, _) = await journal();
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tapBottomDestination(tester, 2);
      await tester.tap(find.text('Hidden coffee').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brew-detail-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('brew-first-drip')), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Notes'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final brew = await database.select(database.brews).getSingle();
      expect(brew.firstDripSeconds, 4);
      expect(brew.notes, 'Secret note');
      await stop(tester);
    });

    testWidgets('Settings change what shows and what is shared', (
      tester,
    ) async {
      final (database, _) = await journal();
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('brew-parameters')));
      await tester.pumpAndSettle();
      Future<void> tapRow(Finder row) async {
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        // Centred, so the group's pinned header does not cover it.
        await Scrollable.ensureVisible(tester.element(row), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
      }

      // Equipment comes before timing, so tools first.
      await tapRow(find.byKey(const ValueKey('parameter-share-tools')));
      await tapRow(find.byKey(const ValueKey('parameter-show-firstDrip')));
      final settings = BrewParameterSettings(database);
      expect(await settings.loadHidden(), {BrewParameter.notes});
      expect(await settings.loadShared(), contains(BrewParameter.tools));
      // The dose always shows: it has no checkbox to hide it.
      expect(find.byKey(const ValueKey('parameter-show-dose')), findsNothing);
      await stop(tester);
    });
  });

  testWidgets('the last shared field explains why it stays selected', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final settings = BrewParameterSettings(database);
    await settings.saveShared({BrewParameter.dose});
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brew-parameters')));
    await tester.pumpAndSettle();
    final dose = find.byKey(const ValueKey('parameter-share-dose'));
    await tester.scrollUntilVisible(
      dose,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    final hint = find.byKey(const ValueKey('parameter-last-shared-hint'));
    expect(hint, findsOneWidget);
    expect(tester.widget<Checkbox>(dose).onChanged, isNull);

    final coffee = find.byKey(const ValueKey('parameter-share-coffee'));
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(coffee);
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(tester.widget<Checkbox>(coffee).onChanged, isNotNull);
    expect(await settings.loadShared(), {
      BrewParameter.dose,
      BrewParameter.coffee,
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('presets hide the finer fields in one tap and show all back', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brew-parameters')));
    await tester.pumpAndSettle();
    final settings = BrewParameterSettings(database);
    final shared = await settings.loadShared();

    await tester.tap(find.byKey(const ValueKey('parameters-preset-essential')));
    await tester.pumpAndSettle();
    expect(await settings.loadHidden(), essentialHiddenParameters);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('parameters-preset-essential')),
          )
          .selected,
      isTrue,
    );
    // Sharing is its own choice and stays as it was.
    expect(await settings.loadShared(), shared);

    await tester.tap(find.byKey(const ValueKey('parameters-preset-all')));
    await tester.pumpAndSettle();
    expect(await settings.loadHidden(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
