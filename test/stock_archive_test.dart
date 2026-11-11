import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  test(
    'mixed stock uses available coffee unless a thaw is explicitly chosen',
    () async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffeeWithComponents(
        name: 'Mixed stock',
        roaster: 'R',
        components: const [],
        initialGrams: 250,
        freeze: const FreezeRequest(grams: 100, frozenDate: '2026-10-07'),
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      final portion = (await repository.frozenPortionsForLot(lot)).single.id;
      final availableBrew = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 20,
        ),
      );
      expect((await repository.coffeeLot(lot))!.remainingGrams, 130);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        100,
      );
      expect(
        (await repository.brew(availableBrew.id))!.frozenPortionId,
        isNull,
      );
      expect(availableBrew.overdrawIncreased, isFalse);
      expect(
        await repository.archiveSuggestionForBrew(availableBrew.id),
        isNull,
      );
      final frozenBrew = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 20,
          frozenSource: FrozenBrewSource(
            portionId: portion,
            lotId: lot,
            grams: 20,
          ),
        ),
      );
      expect((await repository.coffeeLot(lot))!.remainingGrams, 130);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        80,
      );
      expect(frozenBrew.overdrawIncreased, isFalse);
      expect(await repository.archiveSuggestionForBrew(frozenBrew.id), isNull);
      await repository.setCoffeeArchived(coffee, archived: true);
      expect(
        (await repository.brew(availableBrew.id))!.archivedByCoffee,
        isTrue,
      );
      expect((await repository.brew(frozenBrew.id))!.archivedByCoffee, isTrue);
      expect((await repository.coffeeLot(lot))!.remainingGrams, 130);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        80,
      );
      await repository.setCoffeeArchived(coffee, archived: false);
      expect((await repository.brew(availableBrew.id))!.archivedAtMs, isNull);
      expect((await repository.brew(frozenBrew.id))!.archivedAtMs, isNull);
      expect((await repository.coffeeLot(lot))!.remainingGrams, 130);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        80,
      );
    },
  );

  test(
    'an overdraft does not offer archiving while coffee is frozen',
    () async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffeeWithComponents(
        name: 'All frozen',
        roaster: 'R',
        components: const [],
        initialGrams: 250,
        freeze: const FreezeRequest(grams: 250, frozenDate: '2026-10-07'),
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      final outcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 20,
        ),
      );
      expect((await repository.coffeeLot(lot))!.overdrawGrams, 20);
      expect(outcome.overdrawIncreased, isFalse);
      expect(await repository.archiveSuggestionForBrew(outcome.id), isNull);
      final edited = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 25,
        ),
        id: outcome.id,
      );
      expect(edited.overdrawIncreased, isFalse);
      final other = await repository.createCoffee(
        name: 'No frozen coffee',
        roaster: 'R',
        initialGrams: 10,
      );
      final otherLot = (await repository.coffeeLots(other)).single.id;
      final exhausted = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: other,
          lotId: otherLot,
          methodName: 'V60',
          doseGrams: 20,
        ),
      );
      expect(exhausted.overdrawIncreased, isTrue);
    },
  );

  for (final dose in [20.0, 30.0]) {
    test(
      'thawing 20 g for a $dose g brew keeps the remaining portion active',
      () async {
        final database = memoryDatabase();
        addTearDown(database.close);
        final repository = JournalRepository(database);
        final coffee = await repository.createCoffeeWithComponents(
          name: 'All frozen',
          roaster: 'R',
          components: const [],
          initialGrams: 250,
          freeze: const FreezeRequest(grams: 250, frozenDate: '2026-10-07'),
        );
        final lot = (await repository.coffeeLots(coffee)).single.id;
        final portion = (await repository.frozenPortionsForLot(lot)).single.id;
        final outcome = await repository.saveBrewWithOutcome(
          BrewInput(
            coffeeId: coffee,
            lotId: lot,
            methodName: 'V60',
            doseGrams: dose,
            frozenSource: FrozenBrewSource(
              portionId: portion,
              lotId: lot,
              grams: 20,
            ),
          ),
        );
        expect(
          (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
          230,
        );
        expect((await repository.coffeeLot(lot))!.remainingGrams, 0);
        expect(outcome.overdrawIncreased, isFalse);
        expect(await repository.archiveSuggestionForBrew(outcome.id), isNull);
      },
    );
  }

  test(
    'using the last frozen dose offers archiving when nothing remains',
    () async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffeeWithComponents(
        name: 'Last frozen dose',
        roaster: 'R',
        components: const [],
        initialGrams: 20,
        freeze: const FreezeRequest(grams: 20, frozenDate: '2026-10-07'),
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      final portion = (await repository.frozenPortionsForLot(lot)).single.id;
      final outcome = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot,
          methodName: 'V60',
          doseGrams: 20,
          frozenSource: FrozenBrewSource(
            portionId: portion,
            lotId: lot,
            grams: 20,
          ),
        ),
      );
      expect((await repository.coffeeLot(lot))!.remainingGrams, 0);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
        0,
      );
      expect(
        (await repository.archiveSuggestionForBrew(outcome.id))!.remainingGrams,
        0,
      );
      expect(outcome.overdrawIncreased, isFalse);
    },
  );

  test(
    'archive threshold uses this coffee and method, ignoring invalid doses',
    () async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Dose coffee',
        roaster: 'R',
        initialGrams: 100,
      );
      final otherCoffee = await repository.createCoffee(
        name: 'Other coffee',
        roaster: 'R',
      );
      final method = await repository.createMethod(name: 'V60');
      final otherMethod = await repository.createMethod(name: 'V60');
      final id = await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'V60',
        doseGrams: 18,
      );
      await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'V60',
        doseGrams: 22,
      );
      await repository.createBrew(
        coffeeId: coffee,
        methodId: otherMethod,
        methodName: 'V60',
        doseGrams: 50,
      );
      await repository.createBrew(
        coffeeId: otherCoffee,
        methodId: method,
        methodName: 'V60',
        doseGrams: 99,
      );
      final brew = (await repository.brew(id))!;
      final history = [
        ...await repository.allBrews(),
        brew.copyWith(methodId: const Value(null), doseGrams: const Value(20)),
      ];
      expect(meanMethodDose(brew, history), 20);
      expect(
        meanMethodDose(brew, [
          ...history,
          brew.copyWith(doseGrams: const Value(-2)),
          brew.copyWith(doseGrams: const Value(double.nan)),
          brew.copyWith(doseGrams: const Value(null)),
        ]),
        20,
      );
      expect(meanMethodDose(brew, []), isNull);
    },
  );

  test('archive offer requires known total available plus frozen stock below the mean', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Stock coffee',
      roaster: 'R',
      initialGrams: 50,
    );
    final lot = (await repository.coffeeLots(coffeeId)).single;
    final first = await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 18,
    );
    expect(await repository.archiveSuggestionForBrew(first), isNull);
    final second = await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 18,
    );
    final suggestion = (await repository.archiveSuggestionForBrew(second))!;
    expect(suggestion.remainingGrams, 14);
    expect(suggestion.meanDose, 18);
    final coffee = (await repository.coffee(coffeeId))!;
    final brew = (await repository.brew(second))!;
    final history = await repository.allBrews();
    StockArchiveSuggestion? check(List<CoffeeLot> lots, {Coffee? bean}) =>
        stockArchiveSuggestion(
          coffee: bean ?? coffee,
          brew: brew,
          history: history,
          lots: lots,
          portions: const [],
        );
    final remaining = (await repository.coffeeLots(coffeeId)).single;
    expect(
      check([remaining.copyWith(remainingGrams: const Value(18))]),
      isNull,
    );
    expect(
      check([
        remaining,
        remaining.copyWith(id: 'another', remainingGrams: const Value(10)),
      ]),
      isNull,
    );
    expect(
      check([
        remaining,
        remaining.copyWith(id: 'unknown', remainingGrams: const Value(null)),
      ]),
      isNull,
    );
    expect(
      check([remaining], bean: coffee.copyWith(archivedAtMs: const Value(1))),
      isNull,
    );
    await repository.freezeCoffee(
      lotId: lot.id,
      grams: 10,
      frozenDate: '2026-10-04',
    );
    expect(
      (await repository.archiveSuggestionForBrew(second))!.remainingGrams,
      14,
    );
  });

  for (final (initial, frozen, expected) in <(double, double, double?)>[
    (20, 20, 2), // Only a frozen remainder.
    (26, 20, 8), // Available plus frozen remainder.
    (36, 20, null), // Exactly another dose in total.
    (50, 20, null), // Enough available despite a small frozen remainder.
    (18, 18, 0), // Last frozen dose exhausted.
  ]) {
    test(
      'frozen brew archive suggestion counts total stock: $initial/$frozen',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final coffeeId = await repo.createCoffeeWithComponents(
          name: 'Frozen remainder',
          roaster: 'R',
          components: const [],
          initialGrams: initial,
          freeze: FreezeRequest(grams: frozen, frozenDate: '2026-10-07'),
        );
        final lot = (await repo.coffeeLots(coffeeId)).single;
        final portion = (await repo.frozenPortionsForLot(lot.id)).single;
        final saved = await repo.saveBrewWithOutcome(
          BrewInput(
            coffeeId: coffeeId,
            lotId: lot.id,
            methodName: 'Espresso',
            doseGrams: 18,
            frozenSource: FrozenBrewSource(
              portionId: portion.id,
              lotId: lot.id,
              grams: 18,
            ),
          ),
        );
        final suggestion = await repo.archiveSuggestionForBrew(saved.id);
        expect(suggestion?.remainingGrams, expected);
        expect((await repo.coffee(coffeeId))!.archivedAtMs, isNull);
        expect(
          (await repo.coffeeLot(lot.id))!.remainingGrams,
          initial - frozen,
        );
        expect(
          (await repo.frozenPortionsForLot(lot.id)).single.remainingGrams,
          frozen - 18,
        );
      },
    );
  }

  testWidgets(
    'low-stock offer can be declined and is not repeated in the same session',
    (tester) async {
      final database = memoryDatabase();
      addTearDown(database.close);
      final repository = JournalRepository(database);
      final coffeeId = await repository.createCoffee(
        name: 'Almost gone',
        roaster: 'R',
        initialGrams: 35,
      );
      await repository.createMethod(name: 'V60', category: 'pourover');
      await tester.pumpWidget(
        HolyBeansApp(database: database, initialLocale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      Future<void> saveDose(String dose) async {
        await tester.tap(find.text('Brew'));
        await tester.pumpAndSettle();
        final methodField = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Choose a method',
        );
        await tester.scrollUntilVisible(
          methodField,
          200,
          scrollable: verticalScrollable(find.byType(BrewForm)),
        );
        await tester.tap(methodField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('V60').last);
        await tester.pumpAndSettle();
        final field = find.widgetWithText(TextFormField, 'Dose (g)');
        await tester.scrollUntilVisible(
          field,
          200,
          scrollable: verticalScrollable(find.byType(BrewForm)),
        );
        await tester.enterText(field, dose);
        await tester.tap(find.text('Save').last);
        await tester.pumpAndSettle();
      }

      await saveDose('20');
      expect(
        find.byKey(const ValueKey('coffee-archive-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('average 20 g dose with V60'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect((await repository.coffee(coffeeId))!.archivedAtMs, isNull);
      await saveDose('14');
      expect(find.byKey(const ValueKey('coffee-archive-dialog')), findsNothing);
      expect((await repository.coffeeLots(coffeeId)).single.remainingGrams, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}
