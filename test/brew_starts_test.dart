import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late String kenya;
  late String brazil;
  late String v60;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    kenya = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    brazil = await repository.createCoffee(name: 'Brazil', roaster: 'R');
    v60 = await repository.createMethod(name: 'V60', category: 'pourover');
  });
  tearDown(() => database.close());

  Future<String> brew(String coffeeId, int day, {double? rating}) async {
    final lot = (await repository.coffeeLots(coffeeId)).single.id;
    final id = await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot,
      methodId: v60,
      methodName: 'V60',
      doseGrams: 15,
      rating: rating,
      brewedAt: DateTime(2026, 10, day, 9),
    );
    return id;
  }

  test('the dial-in shows the favourite and the latest rated brew', () async {
    final rated = await brew(kenya, 1, rating: 8);
    final unrated = await brew(kenya, 2);
    var found = await repository.dialInFor(coffeeId: kenya, methodId: v60);
    expect(
      (found.last?.id, found.lastRated, found.favorite),
      (rated, true, null),
    );
    // The newest brew, rated or not, is there for its notes.
    expect(found.newest?.id, unrated);

    await repository.setBrewFavorite(rated, favorite: true);
    found = await repository.dialInFor(coffeeId: brazil, methodId: v60);
    expect((found.last, found.lastRated), (null, false));
    found = await repository.dialInFor(coffeeId: kenya, methodId: v60);
    expect(found.favorite?.id, rated);
  });

  test(
    'a new brew starts from the favourite, the coffee, then the method',
    () async {
      expect(
        await repository.methodMemory(coffeeId: kenya, methodId: v60),
        isNull,
        reason: 'the method was never used',
      );
      final brazilBrew = await brew(brazil, 1);
      var memory = await repository.methodMemory(
        coffeeId: kenya,
        methodId: v60,
      );
      expect((memory?.brew.id, memory?.favorite), (brazilBrew, false));

      final first = await brew(kenya, 2);
      await brew(kenya, 3);
      await repository.setBrewFavorite(first, favorite: true);
      memory = await repository.methodMemory(coffeeId: kenya, methodId: v60);
      expect((memory?.brew.id, memory?.favorite), (first, true));
      expect(memory?.toolIds, isEmpty);
    },
  );
  test(
    'archived favorites are excluded and remembered tools use canonical IDs',
    () async {
      final older = await brew(kenya, 1);
      final newer = await brew(kenya, 2);
      await repository.setBrewFavorite(older, favorite: true);
      await repository.setBrewArchived(older, archived: true);
      expect(
        (await repository.methodMemory(
          coffeeId: kenya,
          methodId: v60,
        ))?.brew.id,
        newer,
      );
      final source = await repository.createTool(
        name: 'Paper',
        methodIds: [v60],
      );
      final target = await repository.createTool(
        name: 'Paper canonical',
        methodIds: [v60],
      );
      await repository.saveBrew(
        id: newer,
        coffeeId: kenya,
        methodId: v60,
        methodName: 'V60',
        methodToolIds: [source],
      );
      await repository.mergeTools(sourceId: source, targetId: target);
      final memory = await repository.methodMemory(
        coffeeId: kenya,
        methodId: v60,
      );
      expect(memory?.toolIds, [target]);
      expect(() => memory!.toolIds.clear(), throwsUnsupportedError);
      expect(await repository.brewToolIds(newer), [target]);
    },
  );
}
