import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

class _Reads extends QueryInterceptor {
  String? holdTable;
  bool failTools = false;
  String? failTable;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (failTable != null && statement.contains(failTable!)) {
      failTable = null;
      throw StateError('Catalog unavailable');
    }
    if (failTools && statement.contains('brew_tool_selections')) {
      failTools = false;
      throw StateError('Read interrupted');
    }
    if (holdTable != null && statement.contains(holdTable!)) {
      holdTable = null;
      entered.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Form load did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Reads reads;
  late AppDatabase db;
  late JournalRepository repository;
  late String coffee;
  late String method;
  setUp(() async {
    reads = _Reads();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(reads));
    repository = JournalRepository(db);
    coffee = await repository.createCoffee(name: 'Coffee', roaster: 'R');
    method = await repository.createMethod(name: 'V60', category: 'pourover');
  });
  tearDown(() => db.close());

  for (final table in [
    'recipients',
    'water_profiles',
    'brew_tool_selections',
  ]) {
    test('save waits for $table just like the button', () async {
      final id = await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'V60',
      );
      final existing = await repository.brew(id);
      final coffees = await repository.allCoffees();
      reads.holdTable = table;
      final model = BrewFormModel(
        repository: repository,
        settings: BrewParameterSettings(db),
        coffees: coffees,
        existing: existing,
      );
      addTearDown(model.dispose);
      await reads.entered.future;
      expect(model.busy, isTrue);
      expect(await model.save(), isNull);
      reads.release.complete();
      await _until(() => !model.busy);
      expect(await model.save(), isNotNull);
      expect(await repository.allBrews(), hasLength(1));
    });
  }

  test(
    'catalog errors stay distinct from an empty catalog and can retry',
    () async {
      final coffees = await repository.allCoffees();
      reads.failTable = 'recipients';
      final model = BrewFormModel(
        repository: repository,
        settings: BrewParameterSettings(db),
        coffees: coffees,
        initialCoffeeId: coffee,
        initialMethodId: method,
      );
      addTearDown(model.dispose);
      await _until(() => model.hasLoadError);
      expect(await model.save(), isNull);
      expect(await repository.allBrews(), isEmpty);
      await model.retryLoads();
      await _until(() => !model.busy);
      expect(model.hasLoadError, isFalse);
      expect(await model.save(), isNotNull);
    },
  );

  test(
    'failed saved selection cannot become an empty edit; retry preserves tools',
    () async {
      final tool = await repository.createTool(
        name: 'Paper',
        methodIds: [method],
      );
      final id = await repository.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: 'V60',
        methodToolIds: [tool],
      );
      final existing = await repository.brew(id);
      final coffees = await repository.allCoffees();
      reads.failTools = true;
      final model = BrewFormModel(
        repository: repository,
        settings: BrewParameterSettings(db),
        coffees: coffees,
        existing: existing,
      );
      addTearDown(model.dispose);
      await _until(() => model.hasLoadError);
      model.draft.notes.text = 'Only notes';
      expect(await model.save(), isNull);
      expect(await repository.brewToolIds(id), [tool]);
      await model.retryLoads();
      await _until(() => !model.busy);
      expect(model.selectedToolIds, {tool});
      expect(await model.save(), isNotNull);
      expect(await repository.brewToolIds(id), [tool]);
      expect((await repository.brew(id))!.notes, 'Only notes');
    },
  );
}
