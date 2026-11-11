import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/app_services.dart';

class _HoldMemory extends QueryInterceptor {
  String? coffee;
  bool held = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!held &&
        coffee != null &&
        args.contains(coffee) &&
        statement.contains('is_favorite')) {
      held = true;
      entered.complete();
      await release.future;
    }
    return rows;
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Memory did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final switchBack in [false, true]) {
    test(
      'stale coffee memory cannot override ${switchBack ? 'A after A-B-A' : 'B after A-B'} or end its load',
      () async {
        final hold = _HoldMemory();
        final db = AppDatabase.forTesting(
          NativeDatabase.memory().interceptWith(hold),
        );
        final repository = JournalRepository(db);
        final a = await repository.createCoffee(name: 'A', roaster: 'R');
        final b = await repository.createCoffee(name: 'B', roaster: 'R');
        final method = await repository.createMethod(
          name: 'V60',
          category: 'pourover',
        );
        final first = await repository.createBrew(
          coffeeId: a,
          methodId: method,
          methodName: 'V60',
          doseGrams: 11,
        );
        await repository.createBrew(
          coffeeId: b,
          methodId: method,
          methodName: 'V60',
          doseGrams: 22,
        );
        hold.coffee = a;
        final model = BrewFormModel(
          services: AppServices.forJournal(
            repository,
            parameterSettings: BrewParameterSettings(db),
          ),

          coffees: await repository.allCoffees(),
          initialCoffeeId: a,
          initialMethodId: method,
        );
        try {
          await hold.entered.future.timeout(const Duration(seconds: 5));
          expect(model.loadingMemory, isTrue);
          expect(await model.save(), isNull);
          model.selectCoffee(b);
          await _until(() => model.draft.dose.text == '22' && !model.busy);
          if (switchBack) {
            await repository.saveBrew(
              id: first,
              coffeeId: a,
              methodId: method,
              methodName: 'V60',
              doseGrams: 33,
            );
            model.selectCoffee(a);
            await _until(() => model.draft.dose.text == '33' && !model.busy);
          }
          hold.release.complete();
          // Let the stale request and its completion callback finish.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(model.coffeeId, switchBack ? a : b);
          expect(model.draft.dose.text, switchBack ? '33' : '22');
          expect(model.loadingMemory, isFalse);
        } finally {
          if (!hold.release.isCompleted) hold.release.complete();
          model.dispose();
          await db.close();
        }
      },
    );
  }

  test('disposing a form while memory is pending cannot notify or change its draft', () async {
    final hold = _HoldMemory();
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(hold),
    );
    final repository = JournalRepository(db);
    final coffee = await repository.createCoffee(name: 'A', roaster: 'R');
    final method = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'V60',
      doseGrams: 11,
    );
    hold.coffee = coffee;
    final model = BrewFormModel(
      services: AppServices.forJournal(
        repository,
        parameterSettings: BrewParameterSettings(db),
      ),

      coffees: await repository.allCoffees(),
      initialCoffeeId: coffee,
      initialMethodId: method,
    );
    await hold.entered.future;
    model.dispose();
    hold.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });
  test('pending memory preserves manually edited recipe and grinder', () async {
    final hold = _HoldMemory();
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(hold),
    );
    final repository = JournalRepository(db);
    final coffee = await repository.createCoffee(name: 'A', roaster: 'R');
    final method = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'V60',
      doseGrams: 11,
    );
    hold.coffee = coffee;
    final model = BrewFormModel(
      services: AppServices.forJournal(
        repository,
        parameterSettings: BrewParameterSettings(db),
      ),

      coffees: await repository.allCoffees(),
      initialCoffeeId: coffee,
      initialMethodId: method,
    );
    try {
      await hold.entered.future;
      model.draft.dose.text = '18';
      model.selectGrinder(BrewFormModel.preGroundChoice);
      model.selectWaterProfile(null);
      hold.release.complete();
      await _until(() => !model.busy);
      expect(model.draft.dose.text, '18');
      expect(model.isPreGround, isTrue);
    } finally {
      if (!hold.release.isCompleted) hold.release.complete();
      model.dispose();
      await db.close();
    }
  });
}
