import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  late String coffeeId;
  late String lotId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
    coffeeId = await repository.createCoffee(
      name: 'Kenya',
      roaster: 'R',
      initialGrams: 250,
    );
    lotId = (await repository.coffeeLots(coffeeId)).single.id;
  });

  tearDown(() => database.close());

  Future<double?> left() async =>
      (await repository.coffeeLot(lotId))!.remainingGrams;

  Future<String> brew({double dose = 15}) => repository.createBrew(
    coffeeId: coffeeId,
    lotId: lotId,
    methodName: 'V60',
    doseGrams: dose,
  );

  test('an active brew gives its dose back and takes its curve, photos and '
      'import link with it', () async {
    final id = await brew();
    final keep = await brew(dose: 18);
    expect(await left(), 217);
    await repository.saveScaleCurve(
      id,
      ShotCurve(
        timesMs: const [0, 100],
        flow: const [0, 1],
        weight: const [0, 1],
      ),
    );
    await repository.setBrewPhotos(id, [
      '11111111-1111-4111-8111-111111111111.jpg',
      '22222222-2222-4222-8222-222222222222.jpg',
    ]);
    await repository.setBrewPhotos(keep, [
      '22222222-2222-4222-8222-222222222222.jpg',
    ]);
    await repository.attachMeticulousShot(
      id,
      MeticulousShot(id: 'shot', brewedAt: DateTime(2026), profileName: 'P'),
    );

    final files = await repository.deleteBrew(id);
    expect(files, [
      '11111111-1111-4111-8111-111111111111.jpg',
    ], reason: 'the other is still used');
    expect(await repository.brew(id), isNull);
    expect(await left(), 232);
    expect(await repository.brewCurve(id), isNull);
    expect(await repository.brewPhotos(id), isEmpty);
    expect(
      await repository.importedMeticulousShots(),
      isEmpty,
      reason: 'the shot can be imported again',
    );
    expect(await repository.brew(keep), isNotNull);
  });

  test('an independently archived brew returns its dose only when deleted; one archived '
      'with its coffee cannot be deleted', () async {
    final archived = await brew();
    await repository.setBrewArchived(archived, archived: true);
    expect(await left(), 235);
    await repository.deleteBrew(archived);
    expect(await left(), 250);

    final withCoffee = await brew();
    await repository.setCoffeeArchived(coffeeId, archived: true);
    await expectLater(
      repository.deleteBrew(withCoffee),
      throwsA(isA<BrewArchivedWithCoffeeException>()),
    );
    expect(await repository.brew(withCoffee), isNotNull);
  });
}
