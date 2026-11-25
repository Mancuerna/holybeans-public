import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late String espressoId;
  late String v60Id;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    await repository.createCoffee(
      name: 'Validation coffee',
      roaster: 'Roaster',
      initialGrams: 250,
    );
    espressoId = await repository.createMethod(
      name: 'Espresso',
      category: 'espresso',
    );
    v60Id = await repository.createMethod(name: 'V60', category: 'pourover');
  });

  tearDown(() => database.close());

  for (final language in ['en', 'es']) {
    testWidgets('save reveals and focuses an invalid dose: $language', (
      tester,
    ) async {
      final coffees = await database.select(database.coffees).get();
      await _openForm(tester, repository, coffees, espressoId, language);
      final s = lookupAppLocalizations(Locale(language));
      final dose = find.widgetWithText(TextFormField, '${s.dose} (g)');
      await tester.scrollUntilVisible(dose, 200, scrollable: _scrollable());
      await tester.enterText(dose, '0');
      await tester.fling(_scrollable(), const Offset(0, -6000), 6000);
      await tester.tap(find.text(s.save).last);
      await tester.pumpAndSettle();

      expect(find.text(s.invalidNumber), findsOneWidget);
      expect(_hasFocus(tester, dose), isTrue);
      expect(await database.select(database.brews).get(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  testWidgets(
    'changing coffee asks for a source only when the destination has frozen stock',
    (tester) async {
      final first = (await repository.allCoffees()).single;
      final firstLot = (await repository.coffeeLots(first.id)).single;
      final id = await repository.createBrew(
        coffeeId: first.id,
        lotId: firstLot.id,
        methodName: 'V60',
        methodId: v60Id,
        doseGrams: 15,
      );
      final other = await repository.createCoffee(
        name: 'Campanario',
        roaster: 'R',
        initialGrams: 250,
      );
      final lot = (await repository.coffeeLots(other)).single.id;
      await repository.freezeCoffee(
        lotId: lot,
        grams: 20,
        frozenDate: '2026-09-20',
      );
      final portion = (await repository.frozenPortionsForLot(lot)).single;
      await _openForm(
        tester,
        repository,
        await repository.allCoffees(),
        v60Id,
        'es',
        existing: await repository.brew(id),
      );
      final s = lookupAppLocalizations(const Locale('es'));
      expect(find.text(s.chooseDoseSource), findsNothing);
      final picker = find.byKey(const ValueKey('brew-coffee-picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Campanario').last);
      await tester.pumpAndSettle();
      final field = find.byKey(ValueKey('dose-source-$lot'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(portion.label).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Se devolverán'), findsOneWidget);
      await tester.tap(find.text(s.save).last);
      await tester.pumpAndSettle();
      expect((await repository.brew(id))!.frozenPortionId, portion.id);
      expect((await repository.coffeeLot(lot))!.remainingGrams, 230);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        5,
      );
    },
  );

  testWidgets(
    'source action can move a dose between portions of the same lot',
    (tester) async {
      final coffee = (await repository.allCoffees()).single;
      final lot = (await repository.coffeeLots(coffee.id)).single.id;
      final first = await repository.freezeCoffee(
        lotId: lot,
        grams: 15,
        frozenDate: '2026-09-20',
      );
      final second = await repository.freezeCoffee(
        lotId: lot,
        grams: 15,
        frozenDate: '2026-09-21',
      );
      final id = await repository.createBrew(
        coffeeId: coffee.id,
        lotId: lot,
        methodName: 'V60',
        methodId: v60Id,
        doseGrams: 15,
        frozenSource: FrozenBrewSource(portionId: first, lotId: lot, grams: 15),
      );
      final portions = await repository.frozenPortionsForLot(lot);
      await _openForm(
        tester,
        repository,
        [coffee],
        v60Id,
        'es',
        existing: await repository.brew(id),
        editDoseSource: true,
      );
      final field = find.byKey(ValueKey('dose-source-$lot'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final label = portions.singleWhere((p) => p.id == second).label;
      await tester.tap(find.textContaining(label).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(lookupAppLocalizations(const Locale('es')).save).last,
      );
      await tester.pumpAndSettle();
      final updated = await repository.frozenPortionsForLot(lot);
      expect(updated.singleWhere((p) => p.id == first).remainingGrams, 15);
      expect(updated.singleWhere((p) => p.id == second).remainingGrams, 0);
      expect((await repository.coffeeLot(lot))!.remainingGrams, 220);
      expect((await repository.brew(id))!.frozenPortionId, second);
    },
  );

  testWidgets('timer start does not validate an invalid dose', (tester) async {
    final coffees = await database.select(database.coffees).get();
    await _openForm(tester, repository, coffees, espressoId, 'en');
    final s = lookupAppLocalizations(const Locale('en'));
    final dose = find.widgetWithText(TextFormField, '${s.dose} (g)');
    await tester.scrollUntilVisible(dose, 200, scrollable: _scrollable());
    await tester.enterText(dose, '0');
    final toggle = find.byKey(const ValueKey('extraction-timer'));
    tester.widget<FilledButton>(toggle).onPressed!();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text(s.stopTimer), findsOneWidget);
    expect(find.text(s.invalidNumber), findsNothing);
    expect(await database.select(database.brews).get(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('save expands invalid pour details before revealing the error', (
    tester,
  ) async {
    final coffees = await database.select(database.coffees).get();
    await _openForm(tester, repository, coffees, v60Id, 'en');
    final s = lookupAppLocalizations(const Locale('en'));
    final count = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<int> &&
          widget.decoration.labelText == s.pourCount,
    );
    await tester.scrollUntilVisible(count, 200, scrollable: _scrollable());
    await tester.pumpAndSettle();
    await tester.tap(count);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1').last);
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.pourDetails));
    await tester.pumpAndSettle();
    final water = find.byKey(const ValueKey('pour-1-water'));
    await tester.enterText(water, '0');
    await tester.tap(find.text(s.pourDetails));
    await tester.pumpAndSettle();
    expect(water, findsNothing);

    await tester.fling(_scrollable(), const Offset(0, -6000), 6000);
    await tester.tap(find.text(s.save).last);
    await tester.pumpAndSettle();

    expect(water, findsOneWidget);
    expect(find.text(s.invalidNumber), findsOneWidget);
    expect(_hasFocus(tester, water), isTrue);
    expect(await database.select(database.brews).get(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

bool _hasFocus(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

Finder _scrollable() => find
    .descendant(of: find.byType(BrewForm), matching: find.byType(Scrollable))
    .first;

Future<void> _openForm(
  WidgetTester tester,
  JournalRepository repository,
  List<Coffee> coffees,
  String methodId,
  String language, {
  Brew? existing,
  bool editDoseSource = false,
}) async {
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(language),
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
                  existing: existing,
                  editDoseSource: editDoseSource,
                  initialMethodId: methodId,
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
