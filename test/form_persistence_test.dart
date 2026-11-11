import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/beans/coffee_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/app_services.dart';

class _FailWriteOnce extends QueryInterceptor {
  String? table;

  void _check(String statement) {
    if (table != null && statement.contains('"$table"')) {
      table = null;
      throw StateError('Injected write failure');
    }
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    for (final statement in statements.statements) {
      _check(statement);
    }
    return executor.runBatched(statements);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return executor.runUpdate(statement, args);
  }
}

class _FailCleanup extends PhotoStore {
  _FailCleanup() : super(Directory.systemTemp);
  @override
  Future<void> delete(String? name) async =>
      throw const FileSystemException('Cleanup failure');
}

Future<void> _settle(BrewFormModel model) async {
  for (var i = 0; i < 500; i++) {
    if (!model.busy) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Form catalogs did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late JournalRepository repository;
  late _FailWriteOnce fault;
  setUp(() {
    fault = _FailWriteOnce();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(fault));
    repository = JournalRepository(db);
  });
  tearDown(() => db.close());
  const photo = '11111111-1111-1111-1111-111111111111.jpg';
  const removed = '22222222-2222-2222-2222-222222222222.jpg';
  final curve = ShotCurve(timesMs: [0, 1000], flow: [0, 1], weight: [0, 1]);

  test('brew photo failure rolls back dose, lot opening, tools and curve; retry saves once', () async {
    final coffee = await repository.createCoffee(
      name: 'Coffee',
      roaster: 'R',
      initialGrams: 100,
    );
    final lot = (await repository.coffeeLots(coffee)).single;
    final method = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    Future<BrewSaveOutcome> save() => repository.saveBrewWithOutcome(
      BrewInput(
        coffeeId: coffee,
        lotId: lot.id,
        methodId: method,
        methodName: 'V60',
        doseGrams: 15,
      ),
      photos: [photo],
      curve: curve,
    );
    fault.table = 'brew_photos';
    await expectLater(save(), throwsStateError);
    expect(await db.select(db.brews).get(), isEmpty);
    expect(await db.select(db.brewCurves).get(), isEmpty);
    expect(await db.select(db.brewToolSelections).get(), isEmpty);
    expect((await repository.coffeeLots(coffee)).single.remainingGrams, 100);
    expect((await repository.coffeeLots(coffee)).single.openedDate, isNull);
    final outcome = await save();
    expect(await db.select(db.brews).get(), hasLength(1));
    expect((await repository.coffeeLots(coffee)).single.remainingGrams, 85);
    expect(await repository.brewPhotos(outcome.id), [photo]);
    expect(
      (await repository.brewCurve(outcome.id))!.curve.toJson(),
      curve.toJson(),
    );
  });

  test('brew curve failure rolls back a new preparation and stock', () async {
    final coffee = await repository.createCoffee(
      name: 'Coffee',
      roaster: 'R',
      initialGrams: 100,
    );
    final lot = (await repository.coffeeLots(coffee)).single;
    fault.table = 'brew_curves';
    await expectLater(
      repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot.id,
          methodName: 'V60',
          doseGrams: 15,
        ),
        curve: curve,
      ),
      throwsStateError,
    );
    expect(await db.select(db.brews).get(), isEmpty);
    expect((await repository.coffeeLots(coffee)).single.remainingGrams, 100);
  });

  test(
    'failed brew edit preserves recipe, stock, curve and photo order',
    () async {
      final coffee = await repository.createCoffee(
        name: 'Coffee',
        roaster: 'R',
        initialGrams: 100,
      );
      final lot = (await repository.coffeeLots(coffee)).single;
      final previous = await repository.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          lotId: lot.id,
          methodName: 'V60',
          doseGrams: 15,
        ),
        curve: curve,
        photos: [photo, removed],
      );
      final before = await db.select(db.brews).getSingle();
      fault.table = 'brew_photos';
      await expectLater(
        repository.saveBrewWithOutcome(
          BrewInput(
            coffeeId: coffee,
            lotId: lot.id,
            methodName: 'V60',
            doseGrams: 20,
            notes: 'Changed',
          ),
          id: previous.id,
          photos: [removed],
        ),
        throwsStateError,
      );
      expect(await db.select(db.brews).getSingle(), before);
      expect((await repository.coffeeLots(coffee)).single.remainingGrams, 85);
      expect(await repository.brewPhotos(previous.id), [photo, removed]);
    },
  );

  test(
    'cleanup failure is successful and a completed brew form cannot save twice',
    () async {
      final coffee = await repository.createCoffee(
        name: 'Coffee',
        roaster: 'R',
        initialGrams: 100,
      );
      final method = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      final model = BrewFormModel(
        services: AppServices.forJournal(
          repository,
          parameterSettings: BrewParameterSettings(db),
          photos: _FailCleanup(),
        ),

        coffees: await repository.allCoffees(),
        initialCoffeeId: coffee,
        initialMethodId: method,
      );
      addTearDown(model.dispose);
      await _settle(model);
      model.draft.dose.text = '15';
      model.setPhotos([removed, photo]);
      model.setPhotos([photo]);
      expect(await model.save(), isNotNull);
      expect(await model.save(), isNull);
      expect(await db.select(db.brews).get(), hasLength(1));
      expect((await repository.coffeeLots(coffee)).single.remainingGrams, 85);
    },
  );

  test(
    'coffee extras and photos fail atomically; retry creates one coffee',
    () async {
      final model = CoffeeFormModel(repository: repository);
      addTearDown(model.dispose);
      model.name.text = 'Coffee';
      model.shopUrl.text = 'https://example.com/coffee';
      model.isDecaf = true;
      model.initialGrams.text = '100';
      model.photos.set([photo]);
      fault.table = 'coffee_photos';
      await expectLater(model.save(const []), throwsStateError);
      expect(await repository.allCoffees(), isEmpty);
      expect(await repository.allLots(), isEmpty);
      await model.save(const []);
      final coffee = (await repository.allCoffees()).single;
      expect(coffee.isDecaf, isTrue);
      expect(coffee.shopUrl, 'https://example.com/coffee');
      expect(await repository.coffeePhotos(coffee.id), [photo]);
    },
  );

  test(
    'invalid coffee extras leave no new coffee or purchased stock',
    () async {
      await expectLater(
        repository.createCoffeeWithComponents(
          name: 'Coffee',
          roaster: 'R',
          components: const [],
          initialGrams: 100,
          shopUrl: 'javascript:alert(1)',
        ),
        throwsArgumentError,
      );
      expect(await repository.allCoffees(), isEmpty);
      expect(await repository.allLots(), isEmpty);
    },
  );

  test(
    'failed coffee edit restores all fields, origins, lots and extras',
    () async {
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Coffee',
        roaster: 'R',
        components: const [],
        initialGrams: 100,
        photos: [photo],
      );
      final previous = await repository.coffee(coffeeId);
      final lot = (await repository.coffeeLots(coffeeId)).single;
      fault.table = 'coffee_photos';
      await expectLater(
        repository.updateCoffeeProfileWithComponents(
          id: coffeeId,
          name: 'Changed',
          roaster: 'New',
          paidPriceCents: 2000,
          components: const [],
          inventoryLotId: lot.id,
          initialGrams: 200,
          remainingGrams: 50,
          updateRemainingStock: true,
          isDecaf: true,
          shopUrl: 'https://example.com',
          photos: [removed],
        ),
        throwsStateError,
      );
      expect(await repository.coffee(coffeeId), previous);
      expect((await repository.coffeeLots(coffeeId)).single, lot);
      expect(await repository.coffeePhotos(coffeeId), [photo]);
    },
  );
}
