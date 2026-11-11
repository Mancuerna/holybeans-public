import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

import 'helpers/test_database.dart';

String _isoDaysAgo(int days) => DateTime.now()
    .subtract(Duration(days: days))
    .toIso8601String()
    .substring(0, 10);

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  Future<JournalData> journal() async => JournalData(
    coffees: await database.select(database.coffees).get(),
    brews: await database.select(database.brews).get(),
    lots: await database.select(database.coffeeLots).get(),
    components: await database.select(database.coffeeComponents).get(),
  );

  Future<String> coffeeRoasted(int daysAgo) => repository.createCoffee(
    name: 'Coffee $daysAgo',
    roaster: 'Roaster',
    roastLevel: 'medium',
    roastDate: _isoDaysAgo(daysAgo),
    initialGrams: 250,
  );

  test('the phase follows the style last brewed, or the one asked', () async {
    final espresso = await repository.createMethod(
      name: 'Espresso',
      category: 'espresso',
    );
    final v60 = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final coffeeId = await coffeeRoasted(6);
    final methods = await database.select(database.brewMethods).get();
    var data = await journal();
    final unbrewed = freshnessToday(
      data.coffees.single,
      data: data,
      methods: methods,
      portions: const [],
    );
    // Never brewed: judged for filter.
    expect(unbrewed?.style, BrewStyle.filter);

    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: v60,
      methodName: 'V60',
      doseGrams: 15,
      brewedAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodId: espresso,
      methodName: 'Espresso',
      doseGrams: 18,
    );
    data = await journal();
    final coffee = data.coffees.single;
    final full = coffeeFreshness(
      coffee: coffee,
      lots: data.activeLotsOf(coffeeId),
      coffees: data.coffees,
      brews: const [],
      allLots: data.lots,
      components: data.components,
      methods: methods,
    )!;
    final last = freshnessToday(
      coffee,
      data: data,
      methods: methods,
      portions: const [],
    );
    expect(last, (
      phase: full.phase(BrewStyle.espresso),
      style: BrewStyle.espresso,
      day: full.day,
      window: full.windows[BrewStyle.espresso]!,
    ));
    final asked = freshnessToday(
      coffee,
      data: data,
      methods: methods,
      portions: const [],
      style: BrewStyle.filter,
    );
    expect(asked, (
      phase: full.phase(BrewStyle.filter),
      style: BrewStyle.filter,
      day: full.day,
      window: full.windows[BrewStyle.filter]!,
    ));
  });

  test('archived, frozen-only and undated coffee has no phase', () async {
    final frozenId = await coffeeRoasted(10);
    await coffeeRoasted(12);
    await repository.createCoffee(name: 'Undated', roaster: 'Roaster');
    final lot = (await repository.coffeeLots(frozenId)).single;
    await repository.freezeCoffee(
      lotId: lot.id,
      grams: 250,
      frozenDate: _isoDaysAgo(2),
    );
    final data = await journal();
    final portions = await database.select(database.frozenPortions).get();
    final methods = await database.select(database.brewMethods).get();
    FreshnessToday? today(Coffee coffee) => freshnessToday(
      coffee,
      data: data,
      methods: methods,
      portions: portions,
    );

    final frozen = data.coffees.firstWhere((c) => c.id == frozenId);
    final fresh = data.coffees.firstWhere((c) => c.name == 'Coffee 12');
    final undated = data.coffees.firstWhere((c) => c.name == 'Undated');
    // Freezing stops the clock: all of it is frozen.
    expect(today(frozen), isNull);
    expect(today(fresh), isNotNull);
    expect(today(fresh.copyWith(archivedAtMs: const Value(1))), isNull);
    expect(today(undated), isNull);
  });
}
