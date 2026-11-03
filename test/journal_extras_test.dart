import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/web_link.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  test('web links get a scheme and must look like a web page', () {
    expect(normalizeWebLink(null), isNull);
    expect(normalizeWebLink('  '), isNull);
    expect(normalizeWebLink('tienda.com/cafe'), 'https://tienda.com/cafe');
    expect(normalizeWebLink(' http://shop.es '), 'http://shop.es');
    for (final bad in ['cafe', 'ftp://shop.es', 'https://', 'tienda .com']) {
      expect(() => normalizeWebLink(bad), throwsFormatException, reason: bad);
    }
  });

  test('filter methods keep a jug; espresso brews the first drip', () async {
    final v60 = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
      vesselName: ' Hario 600 ',
      vesselGrams: 312,
    );
    final method = (await repository.watchMethods().first).single;
    expect(
      (method.id, method.vesselName, method.vesselGrams),
      (v60, 'Hario 600', 312.0),
    );
    // A name alone is dropped, and the weight must make sense.
    await repository.updateMethod(id: v60, name: 'V60', vesselName: 'Jug');
    expect((await repository.watchMethods().first).single.vesselName, isNull);
    expect(
      () => repository.createMethod(name: 'Kalita', vesselGrams: 0),
      throwsArgumentError,
    );

    final coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'Espresso',
      beverageGrams: 36,
      firstDripSeconds: 7,
    );
    expect((await repository.brew(brewId))!.firstDripSeconds, 7);
    expect(
      () => repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Espresso',
        firstDripSeconds: 0,
      ),
      throwsArgumentError,
    );
  });

  test(
    'coffees keep decaf, shop page and harvest; water its minerals',
    () async {
      final coffeeId = await repository.createCoffeeWithComponents(
        name: 'Decaf Huila',
        roaster: 'R',
        components: const [
          CoffeeComponentInput(country: 'Colombia', harvest: ' 2025 '),
        ],
      );
      await repository.setCoffeeExtras(
        coffeeId,
        isDecaf: true,
        shopUrl: 'tienda.com/huila',
      );
      expect(
        () => repository.setCoffeeExtras(
          coffeeId,
          isDecaf: true,
          shopUrl: 'no link',
        ),
        throwsArgumentError,
      );
      final coffee = (await repository.coffee(coffeeId))!;
      expect(coffee.isDecaf, isTrue);
      expect(coffee.shopUrl, 'https://tienda.com/huila');
      expect(
        (await repository.coffeeComponents(coffeeId)).single.harvest,
        '2025',
      );

      final waterId = await repository.createWaterProfile(
        name: 'Bottled',
        minerals: const WaterMinerals(calcium: 32.5, magnesium: 8, sulfate: 12),
      );
      expect(
        () => repository.createWaterProfile(
          name: 'Bad',
          minerals: const WaterMinerals(sodium: -1),
        ),
        throwsArgumentError,
      );
      final water = (await repository.watchWaterProfiles().first).single;
      expect(water.id, waterId);
      expect(
        (water.calciumPpm, water.magnesiumPpm, water.sulfatePpm),
        (32.5, 8.0, 12.0),
      );
      expect(water.sodiumPpm, isNull);
    },
  );

  test('the new fields survive a backup', () async {
    final coffeeId = await repository.createCoffeeWithComponents(
      name: 'Decaf Huila',
      roaster: 'R',
      components: const [CoffeeComponentInput(harvest: 'Jan 2025')],
    );
    await repository.setCoffeeExtras(
      coffeeId,
      isDecaf: true,
      shopUrl: 'https://tienda.com/huila',
    );
    await repository.createMethod(
      name: 'V60',
      category: 'pourover',
      vesselName: 'Jug',
      vesselGrams: 300,
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'Espresso',
      firstDripSeconds: 9,
    );
    await repository.createWaterProfile(
      name: 'Bottled',
      minerals: const WaterMinerals(potassium: 1.5, chloride: 4),
    );

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target)
        .restoreJson(await JournalBackup(database).exportJson());
    final copy = JournalRepository(target);
    final coffee = (await copy.coffee(coffeeId))!;
    expect(
      (coffee.isDecaf, coffee.shopUrl),
      (true, 'https://tienda.com/huila'),
    );
    expect((await copy.coffeeComponents(coffeeId)).single.harvest, 'Jan 2025');
    final methods = await target.select(target.brewMethods).get();
    expect(
      {for (final method in methods) method.name: method.vesselGrams},
      {'V60': 300.0, 'Espresso': null},
    );
    final brew = await target.select(target.brews).getSingle();
    expect(brew.firstDripSeconds, 9);
    final water = await target.select(target.waterProfiles).getSingle();
    expect((water.potassiumPpm, water.chloridePpm), (1.5, 4.0));
  });

  test('a v16 backup with its vessel catalog still restores', () async {
    final coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    await repository.createBrew(coffeeId: coffeeId, methodName: 'V60');
    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    backup['version'] = 16;
    final data = backup['data'] as Map<String, dynamic>;
    data['vessels'] = [
      {'id': 'jug', 'name': 'Jug', 'emptyGrams': 300.0, 'notes': null},
    ];
    ((data['brews'] as List).single as Map<String, dynamic>)['vesselId'] =
        'jug';

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(jsonEncode(backup));
    expect(await target.select(target.brews).get(), hasLength(1));
  });

  test('a method remembers its pour recipe, also in backups', () async {
    final v60 = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    final plan = PourPlan.standard(15).copyWith(pours: 4);
    await repository.setMethodPourPlan(v60, plan);
    expect(
      () => repository.setMethodPourPlan(v60, plan.copyWith(pours: 0)),
      throwsArgumentError,
    );
    final source = await JournalBackup(database).exportJson();
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(source);
    final method = await target.select(target.brewMethods).getSingle();
    expect(PourPlan.fromJson(method.pourPlanJson!, doseGrams: 15).pours, 4);

    final bad = jsonDecode(source) as Map<String, dynamic>;
    (((bad['data'] as Map<String, dynamic>)['methods'] as List).single
            as Map<String, dynamic>)['pourPlanJson'] =
        '{"ratio": "much"}';
    await expectLater(
      JournalBackup(target).restoreJson(jsonEncode(bad)),
      throwsFormatException,
    );
  });
}
