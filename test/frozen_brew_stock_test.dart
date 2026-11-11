import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/frozen_brew.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late String coffee;
  late String lot;
  late String portion;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    coffee = await repository.createCoffee(
      name: 'Frozen Kenya',
      roaster: 'R',
      initialGrams: 250,
    );
    lot = (await repository.coffeeLots(coffee)).single.id;
    portion = await repository.freezeCoffee(
      lotId: lot,
      grams: 100,
      frozenDate: '2026-09-20',
    );
  });
  tearDown(() => database.close());

  Future<String> brew({double dose = 18, double thaw = 18}) =>
      repository.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'V60',
        doseGrams: dose,
        frozenSource: FrozenBrewSource(
          portionId: portion,
          lotId: lot,
          grams: thaw,
        ),
      );
  Future<void> stock(double available, double frozen) async {
    expect((await repository.coffeeLot(lot))!.remainingGrams, available);
    expect(
      (await repository.frozenPortionsForLot(lot)).single.remainingGrams,
      frozen,
    );
  }

  Future<void> edit(String id, double dose) => repository.saveBrew(
    id: id,
    coffeeId: coffee,
    lotId: lot,
    methodName: 'V60',
    doseGrams: dose,
  );

  test(
    'deleting returns the frozen dose to the same portion and keeps later uses',
    () async {
      final original = (await repository.frozenPortionsForLot(lot)).single;
      final first = await brew();
      final second = await brew(dose: 10, thaw: 10);
      await stock(150, 72);
      final saved = (await repository.brew(first))!;
      expect((saved.frozenPortionId, saved.frozenDoseGrams), (portion, 18));
      await repository.deleteBrew(first);
      await stock(150, 90);
      final restored = (await repository.frozenPortionsForLot(lot)).single;
      expect(
        (restored.id, restored.label, restored.frozenDate),
        (original.id, original.label, original.frozenDate),
      );
      expect(await repository.brew(second), isNotNull);
      await expectLater(repository.deleteBrew(first), throwsStateError);
      await stock(150, 90);
    },
  );

  test(
    'an exhausted portion returns to frozen with its original date',
    () async {
      final id = await brew(dose: 100, thaw: 100);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.thawedAtMs,
        isNotNull,
      );
      await repository.deleteBrew(id);
      await stock(150, 100);
      expect(
        (await repository.frozenPortionsForLot(lot)).single.thawedAtMs,
        isNull,
      );
    },
  );

  test('mixed doses return each part to its own stock', () async {
    final id = await brew(dose: 20);
    await stock(148, 82);
    final returns = await repository.brewStockReturn(
      (await repository.brew(id))!,
    );
    expect((returns.availableGrams, returns.frozenGrams), (2, 18));
    await repository.deleteBrew(id);
    await stock(150, 100);
  });

  test('extra thawed grams not used by the brew remain available', () async {
    final id = await brew(dose: 15);
    await stock(153, 82);
    await repository.deleteBrew(id);
    await stock(153, 97);
  });

  test(
    'editing adjusts only the change and increasing uses available coffee',
    () async {
      final id = await brew();
      await edit(id, 15);
      await stock(150, 85);
      await edit(id, 15);
      await stock(150, 85);
      await edit(id, 25);
      await stock(140, 85);
      expect((await repository.brew(id))!.frozenDoseGrams, 15);
      await repository.deleteBrew(id);
      await stock(150, 100);
    },
  );

  test('changing the lot returns the original frozen portion', () async {
    final id = await brew();
    final other = await repository.createCoffee(
      name: 'Other',
      roaster: 'R',
      initialGrams: 250,
    );
    final otherLot = (await repository.coffeeLots(other)).single.id;
    await repository.saveBrew(
      id: id,
      coffeeId: other,
      lotId: otherLot,
      methodName: 'V60',
      doseGrams: 18,
    );
    await stock(150, 100);
    expect((await repository.brew(id))!.frozenPortionId, isNull);
    expect((await repository.coffeeLot(otherLot))!.remainingGrams, 232);
  });

  test('archiving and restoring preserve frozen consumption; deleting returns it once', () async {
    final id = await brew();
    await repository.setBrewArchived(id, archived: true);
    await stock(150, 82);
    await repository.setBrewArchived(id, archived: false);
    await stock(150, 82);
    await repository.setBrewArchived(id, archived: true);
    await repository.deleteBrew(id);
    await stock(150, 100);
  });

  test('legacy frozen review is atomic, preserves origin and rejects double attribution', () async {
    final id = await brew();
    final backup = JournalBackup(database);
    final data = jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
    data['version'] = 27;
    final row = data['data']['brews'][0] as Map<String, dynamic>;
    row.remove('stockReviewPending');
    row['archivedAtMs'] = 1;
    row['archivedByCoffee'] = false;
    data['data']['frozenPortions'][0]['remainingGrams'] = 100;
    await backup.restoreJson(jsonEncode(data));
    await expectLater(
      repository.resolveBrewStockReview(id, deduct: false),
      throwsStateError,
    );
    await stock(150, 100);
    expect((await repository.brew(id))!.stockReviewPending, true);
    await repository.resolveBrewStockReview(id, deduct: true);
    await repository.resolveBrewStockReview(id, deduct: true);
    await stock(150, 82);
    await backup.restoreJson(await backup.exportJson());
    await repository.deleteBrew(id);
    await stock(150, 100);
  });

  test('a frozen dose archived with its coffee remains consumed', () async {
    final id = await brew();
    await repository.setCoffeeArchived(coffee, archived: true);
    await stock(150, 82);
    await expectLater(
      edit(id, 15),
      throwsA(isA<BrewArchivedWithCoffeeException>()),
    );
    await stock(150, 82);
    await repository.setCoffeeArchived(coffee, archived: false);
    await edit(id, 15);
    await stock(150, 85);
    await repository.deleteBrew(id);
    await stock(150, 100);
  });

  test(
    'deleting the original portion makes the dose return to available coffee',
    () async {
      final id = await brew();
      await repository.deleteFrozenPortion(portion);
      final saved = (await repository.brew(id))!;
      expect((saved.frozenPortionId, saved.frozenDoseGrams), (null, null));
      await repository.deleteBrew(id);
      expect((await repository.coffeeLot(lot))!.remainingGrams, 250);
    },
  );

  test('a failed save rolls back its thaw', () async {
    final method = await repository.createMethod(name: 'V60');
    await expectLater(
      repository.createBrew(
        coffeeId: coffee,
        lotId: lot,
        methodName: 'Wrong name',
        methodId: method,
        doseGrams: 18,
        frozenSource: FrozenBrewSource(
          portionId: portion,
          lotId: lot,
          grams: 18,
        ),
      ),
      throwsArgumentError,
    );
    await stock(150, 100);
    expect(await database.select(database.brews).get(), isEmpty);
  });

  test('an unavailable thaw does not consume stock or create a brew', () async {
    await expectLater(brew(thaw: 101), throwsStateError);
    await stock(150, 100);
    expect(await database.select(database.brews).get(), isEmpty);
  });

  test(
    'archived brew keeps its frozen dose unavailable; recovery is neutral',
    () async {
      final archived = await brew(dose: 100, thaw: 100);
      await repository.setBrewArchived(archived, archived: true);
      await expectLater(brew(dose: 90, thaw: 90), throwsStateError);
      await repository.setBrewArchived(archived, archived: false);
      await stock(150, 0);
      expect((await repository.brew(archived))!.archivedAtMs, isNull);
    },
  );

  test(
    'backup preserves origin and rejects inconsistent frozen sources',
    () async {
      final id = await brew(dose: 20);
      final backup = JournalBackup(database);
      final source = await backup.exportJson();
      expect(jsonDecode(source)['version'], JournalBackup.version);
      await repository.deleteBrew(id);
      await backup.restoreJson(source);
      await repository.deleteBrew(id);
      await stock(150, 100);
      final invalid = jsonDecode(source) as Map<String, dynamic>;
      invalid['data']['brews'][0]['frozenDoseGrams'] = 21;
      await expectLater(
        backup.restoreJson(jsonEncode(invalid)),
        throwsFormatException,
      );
      await stock(150, 100);
      final unconsumed = jsonDecode(source) as Map<String, dynamic>;
      unconsumed['data']['frozenPortions'][0]['remainingGrams'] = 100;
      await expectLater(
        backup.restoreJson(jsonEncode(unconsumed)),
        throwsFormatException,
      );
      await stock(150, 100);
    },
  );
}
