import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

import 'helpers/test_database.dart';

Future<void> ready(BrewFormModel model) async {
  for (var i = 0; i < 500 && model.busy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(model.busy, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fresh in [0.0, 5.0, 25.0]) {
    test(
      'direct Brew with $fresh fresh grams preserves stock and origin',
      () async {
        final db = memoryDatabase();
        final repo = JournalRepository(db);
        final coffee = await repo.createCoffee(
          name: 'Frozen',
          roaster: 'R',
          initialGrams: 900 + fresh,
        );
        final lot = (await repo.coffeeLots(coffee)).single.id;
        await repo.freezeCoffee(
          lotId: lot,
          grams: 900,
          frozenDate: '2026-10-19',
        );
        final method = await repo.createMethod(
          name: 'V60',
          category: 'pourover',
        );
        final model = BrewFormModel(
          repository: repo,
          settings: BrewParameterSettings(db),
          coffees: await repo.allCoffees(),
          initialCoffeeId: coffee,
          initialMethodId: method,
          initialDoseGrams: 18,
        );
        try {
          await ready(model);
          model.draft.dose.text = '18';
          var prompts = 0;
          final result = await model.save(
            chooseFrozen: (portions, grams) async {
              prompts++;
              expect(grams, 18 - fresh);
              return portions.single;
            },
          );
          expect(result, isNotNull);
          expect(prompts, fresh < 18 ? 1 : 0);
          final brew = (await repo.allBrews()).single;
          expect(brew.frozenDoseGrams, fresh < 18 ? 18 - fresh : null);
          expect((await repo.coffeeLot(lot))!.overdrawGrams ?? 0, 0);
          expect(
            (await repo.frozenPortionsForLot(lot)).single.remainingGrams,
            fresh < 18 ? 900 - (18 - fresh) : 900,
          );
          await repo.deleteBrew(brew.id);
          expect(
            (await repo.frozenPortionsForLot(lot)).single.remainingGrams,
            900,
          );
          expect((await repo.coffeeLot(lot))!.remainingGrams, fresh);
        } finally {
          model.dispose();
          await db.close();
        }
      },
    );
  }
  test('cancel and double save leave all frozen coffee untouched', () async {
    final db = memoryDatabase();
    final repo = JournalRepository(db);
    final coffee = await repo.createCoffeeWithComponents(
      name: 'Frozen',
      roaster: 'R',
      components: const [],
      initialGrams: 900,
      freeze: const FreezeRequest(grams: 900, frozenDate: '2026-10-19'),
    );
    final lot = (await repo.coffeeLots(coffee)).single.id;
    final method = await repo.createMethod(name: 'V60', category: 'pourover');
    final model = BrewFormModel(
      repository: repo,
      settings: BrewParameterSettings(db),
      coffees: await repo.allCoffees(),
      initialCoffeeId: coffee,
      initialMethodId: method,
      initialDoseGrams: 18,
    );
    try {
      await ready(model);
      final entered = Completer<void>();
      final response = Completer<FrozenPortion?>();
      final saving = model.save(
        chooseFrozen: (_, _) {
          entered.complete();
          return response.future;
        },
      );
      await entered.future;
      expect(await model.save(), isNull);
      response.complete(null);
      expect(await saving, isNull);
      expect(await repo.allBrews(), isEmpty);
      expect((await repo.frozenPortionsForLot(lot)).single.remainingGrams, 900);
      expect((await repo.coffeeLot(lot))!.remainingGrams, 0);
    } finally {
      model.dispose();
      await db.close();
    }
  });
}
