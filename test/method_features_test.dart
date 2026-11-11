import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/equipment/equipment_page.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late String v60Id;
  late String espressoId;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Memory coffee',
      roaster: 'Test roaster',
    );
    v60Id = await repository.createMethod(name: 'V60', category: 'pourover');
    espressoId = await repository.createMethod(
      name: 'Espresso',
      category: 'espresso',
    );
    final variableId = await repository.createGrinder(
      name: 'Variable grinder',
      hasAdjustableRpm: true,
      hasAdjustableFeederRpm: true,
    );
    final handId = await repository.createGrinder(name: 'Hand grinder');
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: v60Id,
      methodName: 'V60',
      grinderId: variableId,
      grindSetting: '18 clicks',
      grindRpm: 1200,
      feederRpm: 60,
      doseGrams: 18,
      waterGrams: 288,
      beverageGrams: 250,
      temperatureC: 94,
      bloomSeconds: 40,
      timeSeconds: 180,
      rating: 8,
      brewedAt: DateTime(2026, 9, 28, 9),
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: espressoId,
      methodName: 'Espresso',
      grinderId: handId,
      grindSetting: '8',
      doseGrams: 18,
      beverageGrams: 36,
      pressureBar: 9,
      preinfusionSeconds: 6,
      brewedAt: DateTime(2026, 9, 28, 10),
    );
  });

  tearDown(() => database.close());

  testWidgets('a new brew remembers the last values used with each method', (
    tester,
  ) async {
    _setNarrowScreen(tester);
    final coffees = await database.select(database.coffees).get();
    await _openForm(tester, repository, coffees);

    await _chooseMethod(tester, 'V60');
    expect(find.byKey(const ValueKey('method-memory-hint')), findsOneWidget);
    expect(await _fieldText(tester, 'Grind setting'), '18 clicks');
    expect(await _fieldText(tester, 'RPM'), '1200');
    expect(await _fieldText(tester, 'Feeder RPM'), '60');
    expect(await _fieldText(tester, 'Dose (g)'), '18');
    expect(await _fieldText(tester, 'Water (g)'), '288');
    expect(await _fieldText(tester, 'Temperature (°C)'), '94');
    expect(await _fieldText(tester, 'Total bloom time (s)'), '40');
    // Results are not copied.
    expect(await _fieldText(tester, 'Beverage weight (g)'), isEmpty);
    expect(await _fieldText(tester, 'Minutes'), isEmpty);

    // Something typed by hand survives switching to another method.
    await _fieldText(tester, 'Dose (g)');
    await tester.enterText(_field('Dose (g)'), '20');
    await _chooseMethod(tester, 'Espresso');
    expect(await _fieldText(tester, 'Dose (g)'), '20');
    // The espresso yield is a result too.
    expect(await _fieldText(tester, 'Beverage weight (g)'), isEmpty);
    expect(_field('Water (g)'), findsNothing);
    expect(await _fieldText(tester, 'Peak pressure (bar)'), '9');
    expect(await _fieldText(tester, 'Pre-infusion (s)'), '6');
    expect(await _fieldText(tester, 'Grind setting'), '8');
    // The hand grinder has fixed speed, so RPM and bloom disappear.
    expect(_field('RPM'), findsNothing);
    expect(_field('Total bloom time (s)'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
    'Brix input computes TDS and switches back to direct measurement',
    (tester) async {
      _setNarrowScreen(tester);
      await _openForm(
        tester,
        repository,
        await database.select(database.coffees).get(),
      );
      await _chooseMethod(tester, 'Espresso');
      await tester.scrollUntilVisible(
        find.text('Measure in Brix'),
        200,
        scrollable: _scrollable(),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Measure in Brix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measure in Brix'));
      await tester.pumpAndSettle();
      await _fieldText(tester, 'Brix (°Bx)');
      await tester.enterText(_field('Brix (°Bx)'), '8');
      await tester.pumpAndSettle();
      expect(find.text('Estimated TDS: 6.80 %'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Measure in Brix'),
        -150,
        scrollable: _scrollable(),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Measure in Brix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measure in Brix'));
      await tester.pumpAndSettle();
      expect(_field('TDS (%)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  for (final language in ['en', 'es']) {
    testWidgets(
      'first drip stays in timing and pressure is labelled as peak: $language',
      (tester) async {
        _setNarrowScreen(tester);
        final coffees = await database.select(database.coffees).get();
        await _openForm(tester, repository, coffees, locale: Locale(language));
        final strings = lookupAppLocalizations(Locale(language));
        await _chooseMethod(tester, 'Espresso', label: strings.selectMethod);
        final label = language == 'en'
            ? 'Peak pressure (bar)'
            : 'Presión máxima (bar)';
        expect(await _fieldText(tester, label), '9');
        final timer = find.byKey(const ValueKey('extraction-timer'));
        final firstDrip = find.byKey(const ValueKey('brew-first-drip'));
        final beverage = _field('${strings.brewOutput} (g)');
        final tds = _field('${strings.tds} (%)');
        expect(firstDrip, findsOneWidget);
        expect(
          tester.getTopLeft(firstDrip).dy,
          greaterThan(tester.getTopLeft(timer).dy),
        );
        expect(
          tester.getTopLeft(firstDrip).dy,
          lessThan(tester.getTopLeft(beverage).dy),
        );
        expect(
          tester.getTopLeft(firstDrip).dy,
          lessThan(tester.getTopLeft(tds).dy),
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }

  testWidgets('the timer can mark the bloom and hidden fields stay out', (
    tester,
  ) async {
    _setNarrowScreen(tester);
    await BrewParameterSettings(database)
        .saveHidden({BrewParameter.temperature, BrewParameter.tds});
    final coffees = await database.select(database.coffees).get();
    await _openForm(tester, repository, coffees);
    await _chooseMethod(tester, 'V60');

    // Hidden fields stay out even when the method memory prefills them
    // (the last V60 brew had a temperature); the value is still kept.
    expect(_field('Temperature (°C)'), findsNothing);
    expect(_field('TDS (%)'), findsNothing);

    final timer = find.byKey(const ValueKey('extraction-timer'));
    await tester.scrollUntilVisible(timer, 240, scrollable: _scrollable());
    await tester.pumpAndSettle();
    await tester.tap(timer);
    await tester.pump(const Duration(seconds: 35));
    await tester.tap(find.byKey(const ValueKey('extraction-timer-mark')));
    await tester.pump();
    await tester.tap(timer);
    await tester.pump();
    expect(await _fieldText(tester, 'Total bloom time (s)'), '35');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('recipe and result keep the same hierarchy across methods', (
    tester,
  ) async {
    _setNarrowScreen(tester);
    final coffees = await database.select(database.coffees).get();
    await _openForm(tester, repository, coffees);
    final s = lookupAppLocalizations(const Locale('en'));
    for (final method in ['Espresso', 'V60']) {
      await _chooseMethod(tester, method);
      for (final label in [s.recipeSection, s.resultSection]) {
        final heading = find.text(label);
        expect(heading, findsOneWidget);
        expect(
          tester.widget<Text>(heading).style,
          Theme.of(tester.element(heading)).textTheme.titleMedium,
        );
      }
      expect(find.text(s.optionalMeasure), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('method cards show usage and open filtered brews or a new brew', (
    tester,
  ) async {
    _setNarrowScreen(tester);
    // An archived brew still counts as the method's, and is listed.
    final coffee = await database.select(database.coffees).getSingle();
    final archived = await repository.createBrew(
      coffeeId: coffee.id,
      methodId: v60Id,
      methodName: 'V60',
      grindSetting: '20 clicks',
      doseGrams: 15,
      rating: 6,
      brewedAt: DateTime(2026, 9, 20, 9),
    );
    await repository.setBrewArchived(archived, archived: true);
    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 3.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(ValueKey('method-stats-$v60Id')),
      180,
      scrollable: find
          .descendant(
            of: find.byType(EquipmentPage),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    final stats = tester.widget<Text>(
      find.byKey(ValueKey('method-stats-$v60Id')),
    );
    expect(stats.data, contains('2 brews'));
    expect(stats.data, contains('Average rating 7'));

    await tester.ensureVisible(find.byKey(ValueKey('method-brews-$v60Id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('method-brews-$v60Id')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('history-filter-button')),
          )
          .tooltip,
      '1 active filter',
      reason: 'the method',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('history-show-archived')),
          )
          .isSelected,
      isTrue,
      reason: 'archived brews count on the method card too',
    );
    expect(find.byType(Card), findsNWidgets(2));

    await tester.tapAt(
      Offset(bounds.left + bounds.width * 3.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    final lastAction = find.byKey(ValueKey('brew-with-method-$espressoId'));
    await tester.ensureVisible(lastAction);
    await tester.pumpAndSettle();
    final equipmentScrollable = find
        .descendant(
          of: find.byType(EquipmentPage),
          matching: find.byType(Scrollable),
        )
        .last;
    await tester.drag(equipmentScrollable, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(lastAction).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(FloatingActionButton)).top),
    );
    await tester.tap(lastAction);
    await tester.pumpAndSettle();
    expect(find.byType(BrewForm), findsOneWidget);
    expect(await _fieldText(tester, 'Peak pressure (bar)'), '9');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('renamed methods keep their brews accessible by id', (
    tester,
  ) async {
    _setNarrowScreen(tester);
    final methodId = await repository.createMethod(
      name: 'Old name',
      category: 'pourover',
    );
    final coffee = await database.select(database.coffees).getSingle();
    await repository.createBrew(
      coffeeId: coffee.id,
      methodId: methodId,
      methodName: 'Old name',
      rating: 8,
    );
    final archived = await repository.createBrew(
      coffeeId: coffee.id,
      methodId: methodId,
      methodName: 'Old name',
      rating: 7,
    );
    await repository.setBrewArchived(archived, archived: true);
    await repository.updateMethod(id: methodId, name: 'New name');

    await tester.pumpWidget(
      HolyBeansApp(
        services: AppServices(database: database),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final navigation = find.byType(NavigationBar);
    final bounds = tester.getRect(navigation);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 3.5 / 4, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    final seeBrews = find.byKey(ValueKey('method-brews-$methodId'));
    await tester.ensureVisible(seeBrews);
    await tester.tap(seeBrews);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('history-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('New name'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Clear filter: New name'));
    await tester.tap(find.byTooltip('Clear filter: New name'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

void _setNarrowScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openForm(
  WidgetTester tester,
  JournalRepository repository,
  List<Coffee> coffees, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    localizedApp(
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BrewForm(
                  services: AppServices.forJournal(
                    repository,
                    parameterSettings: BrewParameterSettings(
                      repository.database,
                    ),
                  ),

                  coffees: coffees,
                ),
              ),
              child: const Text('Open brew form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open brew form'));
  await tester.pumpAndSettle();
}

Finder _scrollable() => find
    .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
    .first;

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _chooseMethod(
  WidgetTester tester,
  String name, {
  String? label,
}) async {
  final selector = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == (label ?? 'Choose a method'),
  );
  await tester.fling(_scrollable(), const Offset(0, 4000), 6000);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(selector, 200, scrollable: _scrollable());
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<String> _fieldText(WidgetTester tester, String label) async {
  final field = _field(label);
  final scrollable = _scrollable();
  // Start from the top so the field is always found by scrolling down.
  await tester.fling(scrollable, const Offset(0, 4000), 6000);
  await tester.pumpAndSettle();
  if (label == 'Total bloom time (s)') {
    final details = find.byKey(const ValueKey('brew-pour-details'));
    await tester.scrollUntilVisible(details, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    final tile = tester.widget<ExpansionTile>(details);
    if (!tile.initiallyExpanded) {
      await tester.tap(find.text('Bloom and pour details'));
      await tester.pumpAndSettle();
    }
  }
  await tester.scrollUntilVisible(field, 200, scrollable: scrollable);
  await tester.pumpAndSettle();
  return tester.widget<TextFormField>(field).controller!.text;
}
