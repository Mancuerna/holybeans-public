import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/equipment/equipment_page.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUpAll(() async {
    // Every database in this file uses its own in-memory SQLite executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('es');
  });

  setUp(() {
    database = memoryDatabase();
    repository = JournalRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('equipment tabs keep full size Spanish labels at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(String language) => localizedApp(
      locale: Locale(language),
      home: Scaffold(
        body: EquipmentPage(
          repository: repository,
          section: EquipmentSection.methods,
          onSectionChanged: (_) {},
          showArchived: false,
        ),
      ),
    );
    await tester.pumpWidget(app('es'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TabBar>(find.byKey(const ValueKey('equipment-tabs')))
          .isScrollable,
      true,
    );
    expect(find.text('Accesorios'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Accesorios'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TabBar>(find.byKey(const ValueKey('equipment-tabs')))
          .isScrollable,
      true,
    );
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  test('water catalog validates values and retains brew snapshots', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Water test coffee',
      roaster: 'Local',
    );
    final profileId = await repository.createWaterProfile(
      name: '  My tap water  ',
      ghPpmAsCaCO3: 70,
      khPpmAsCaCO3: 40,
      tdsPpm: 110,
      ph: 7.2,
      notes: '  Filtered  ',
    );
    expect(
      (await repository.watchWaterProfiles().first).single.name,
      'My tap water',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      waterProfileId: profileId,
    );
    final initialBrew = await (database.select(
      database.brews,
    )..where((brew) => brew.id.equals(brewId))).getSingle();
    expect(initialBrew.waterProfileId, profileId);
    expect(initialBrew.waterProfileName, 'My tap water');

    await repository.updateWaterProfile(
      id: profileId,
      name: 'Home water',
      ghPpmAsCaCO3: 75,
      khPpmAsCaCO3: 45,
      tdsPpm: 120,
      ph: 7.4,
      notes: 'Updated',
    );
    await repository.setWaterProfileArchived(profileId, archived: true);
    expect(await repository.watchWaterProfiles().first, isEmpty);
    expect(
      (await repository.watchWaterProfiles(includeArchived: true).first)
          .single
          .name,
      'Home water',
    );
    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        waterProfileId: profileId,
      ),
      throwsStateError,
    );

    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      methodName: 'V60',
      waterProfileId: profileId,
    );
    final editedBrew = await (database.select(
      database.brews,
    )..where((brew) => brew.id.equals(brewId))).getSingle();
    expect(editedBrew.waterProfileId, profileId);
    expect(editedBrew.waterProfileName, 'My tap water');

    await repository.setWaterProfileArchived(profileId, archived: false);
    final replacementId = await repository.createWaterProfile(
      name: 'Third Wave',
    );
    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      methodName: 'V60',
      waterProfileId: replacementId,
    );
    final changedBrew = await (database.select(
      database.brews,
    )..where((brew) => brew.id.equals(brewId))).getSingle();
    expect(changedBrew.waterProfileId, replacementId);
    expect(changedBrew.waterProfileName, 'Third Wave');

    for (final invalid in [double.nan, double.infinity, -0.1]) {
      await expectLater(
        repository.createWaterProfile(
          name: 'Invalid GH',
          ghPpmAsCaCO3: invalid,
        ),
        throwsArgumentError,
      );
    }
    for (final invalidPh in [-0.1, 14.1, double.nan]) {
      await expectLater(
        repository.createWaterProfile(name: 'Invalid pH', ph: invalidPh),
        throwsArgumentError,
      );
    }
    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        waterProfileId: 'missing-water-profile',
      ),
      throwsStateError,
    );
  });

  test(
    'catalog CRUD, brew links, snapshots and method tools stay consistent',
    () async {
      final methodId = await repository.createMethod(
        name: '  Hario Switch ',
        category: 'immersion',
        templateType: 'pour_over',
        notes: '  Bloom first  ',
      );
      final otherMethodId = await repository.createMethod(name: 'AeroPress');
      final grinderId = await repository.createGrinder(
        name: '  C40  ',
        notes: '  Red Clix  ',
      );
      final toolId = await repository.createMethodTool(
        methodId: methodId,
        name: 'Paper filter',
      );
      final otherToolId = await repository.createMethodTool(
        methodId: otherMethodId,
        name: 'Metal filter',
      );
      expect((await repository.watchMethods().first).length, 2);
      expect((await repository.watchGrinders().first).single.notes, 'Red Clix');
      expect((await repository.methodTools(methodId)).single.id, toolId);

      final coffeeId = await repository.createCoffee(
        name: 'Kieni',
        roaster: 'Loma',
      );
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Hario Switch',
        methodId: methodId,
        grinderId: grinderId,
        grinderName: 'C40',
        grindSetting: '  22 clicks  ',
        methodToolIds: [toolId],
      );
      var brew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingle();
      expect(brew.methodId, methodId);
      expect(brew.grinderId, grinderId);
      expect(brew.methodName, 'Hario Switch');
      expect(brew.grinderName, 'C40');
      expect(brew.grindSetting, '22 clicks');
      expect(await repository.brewToolIds(brewId), [toolId]);

      await repository.updateMethod(
        id: methodId,
        name: 'Switch 03',
        category: 'immersion',
        templateType: 'pour_over',
        notes: 'Updated recipe',
      );
      await repository.updateGrinder(id: grinderId, name: 'Comandante C40');
      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        methodName: 'Switch 03',
        methodId: methodId,
        grinderId: grinderId,
        grinderName: 'Comandante C40',
      );
      brew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingle();
      expect(brew.methodName, 'Hario Switch');
      expect(brew.grinderName, 'C40');
      expect(brew.grindSetting, isNull);
      expect(await repository.brewToolIds(brewId), [toolId]);

      await expectLater(
        repository.saveBrew(
          id: brewId,
          coffeeId: coffeeId,
          methodName: 'Switch 03',
          methodId: methodId,
          methodToolIds: [otherToolId],
        ),
        throwsStateError,
      );
      await expectLater(
        repository.createBrew(
          coffeeId: coffeeId,
          methodName: 'Switch 03',
          methodId: 'missing-method',
        ),
        throwsStateError,
      );
      await expectLater(
        repository.createBrew(
          coffeeId: coffeeId,
          methodName: 'AeroPress',
          methodId: methodId,
        ),
        throwsArgumentError,
      );
      expect((await database.select(database.brews).get()).length, 1);
      expect(await repository.brewToolIds(brewId), [toolId]);

      await repository.setMethodToolArchived(toolId, archived: true);
      expect(await repository.methodTools(methodId), isEmpty);
      expect(
        (await repository.methodTools(
          methodId,
          includeArchived: true,
        )).single.id,
        toolId,
      );
      await repository.setGrinderArchived(grinderId, archived: true);
      await repository.setMethodArchived(methodId, archived: true);
      expect((await repository.watchMethods().first).single.id, otherMethodId);
      expect(await repository.watchGrinders().first, isEmpty);
      await repository.setMethodArchived(methodId, archived: false);
      await repository.setGrinderArchived(grinderId, archived: false);
    },
  );

  test('pre-ground brews clear grind setting without a grinder link', () async {
    final coffeeId = await repository.createCoffee(name: 'Kieni', roaster: 'R');
    final methodId = await repository.createMethod(name: 'V60');
    final grinderId = await repository.createGrinder(name: 'C40');
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      methodId: methodId,
      grinderName: 'C40',
      grinderId: grinderId,
      grindSetting: '18 clicks',
      timeSeconds: 180,
    );

    var brew = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();
    expect(brew.isPreGround, isFalse);

    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      methodName: 'V60',
      methodId: methodId,
      isPreGround: true,
      grindSetting: '18 clicks',
      timeSeconds: 180,
    );
    brew = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();
    expect(brew.isPreGround, isTrue);
    expect(brew.grinderId, isNull);
    expect(brew.grinderName, isNull);
    expect(brew.grindSetting, isNull);
    expect(brew.timeSeconds, 180);

    await expectLater(
      repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        methodName: 'V60',
        methodId: methodId,
        grinderId: grinderId,
        isPreGround: true,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        grinderName: 'C40',
        isPreGround: true,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        timeSeconds: 0,
      ),
      throwsArgumentError,
    );
  });

  test(
    'legacy brew calls create and reuse method and grinder catalogs',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Kieni',
        roaster: 'Loma',
      );
      final firstId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: '  V60 ',
        grinderName: '  C40 ',
      );
      final secondId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'v60',
        grinderName: 'c40',
      );
      final first = (await database.select(database.brews).get()).singleWhere(
        (brew) => brew.id == firstId,
      );
      final second = (await database.select(database.brews).get()).singleWhere(
        (brew) => brew.id == secondId,
      );
      expect(first.methodId, second.methodId);
      expect(first.grinderId, second.grinderId);
      expect(await database.select(database.brewMethods).get(), hasLength(1));
      expect(await database.select(database.grinders).get(), hasLength(1));
    },
  );

  test(
    'legacy save creates active rows instead of unarchiving catalog rows',
    () async {
      final methodId = await repository.createMethod(name: 'Archived method');
      final grinderId = await repository.createGrinder(
        name: 'Archived grinder',
      );
      await repository.setMethodArchived(methodId, archived: true);
      await repository.setGrinderArchived(grinderId, archived: true);
      final coffeeId = await repository.createCoffee(
        name: 'Kieni',
        roaster: 'Loma',
      );

      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Archived method',
        grinderName: 'Archived grinder',
      );
      final brew = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(brewId))).getSingle();
      expect(brew.methodId, isNot(methodId));
      expect(brew.grinderId, isNot(grinderId));
      expect(
        (await (database.select(
          database.brewMethods,
        )..where((row) => row.id.equals(methodId))).getSingle()).archivedAtMs,
        isNotNull,
      );
      expect(
        (await (database.select(
          database.grinders,
        )..where((row) => row.id.equals(grinderId))).getSingle()).archivedAtMs,
        isNotNull,
      );
    },
  );

  test(
    'legacy edit keeps its archived grinder link after a grinder rename',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Kieni',
        roaster: 'Loma',
      );
      final grinderId = await repository.createGrinder(name: 'C40');
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        grinderName: 'C40',
      );
      expect(
        (await database.select(database.brews).getSingle()).grinderId,
        grinderId,
      );

      await repository.updateGrinder(id: grinderId, name: 'Comandante C40');
      await repository.setGrinderArchived(grinderId, archived: true);
      await repository.saveBrew(
        id: brewId,
        coffeeId: coffeeId,
        methodName: 'V60',
        grinderName: 'C40',
      );

      final brew = await database.select(database.brews).getSingle();
      final grinder = await database.select(database.grinders).getSingle();
      expect(brew.grinderId, grinderId);
      expect(brew.grinderName, 'C40');
      expect(grinder.name, 'Comandante C40');
      expect(grinder.archivedAtMs, isNotNull);
      expect(await database.select(database.grinders).get(), hasLength(1));
    },
  );

  test('RPM is kept only for grinders with adjustable speed', () async {
    final coffeeId = await repository.createCoffee(
      name: 'RPM coffee',
      roaster: 'Test roaster',
    );
    final fixedId = await repository.createGrinder(name: 'Hand grinder');
    final variableId = await repository.createGrinder(
      name: 'Variable grinder',
      hasAdjustableRpm: true,
    );
    final variableBrew = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'Espresso',
      grinderId: variableId,
      grindRpm: 1200,
      pressureBar: 9,
      preinfusionSeconds: 6,
    );
    final fixedBrew = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      grinderId: fixedId,
      grindRpm: 900,
      bloomSeconds: 40,
    );
    final preGroundBrew = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      isPreGround: true,
      grindRpm: 900,
    );
    Future<Brew> brew(String id) => (database.select(
      database.brews,
    )..where((row) => row.id.equals(id))).getSingle();
    final variable = await brew(variableBrew);
    expect(variable.grindRpm, 1200);
    expect(variable.pressureBar, 9);
    expect(variable.preinfusionSeconds, 6);
    final fixed = await brew(fixedBrew);
    expect(fixed.grindRpm, isNull);
    expect(fixed.bloomSeconds, 40);
    expect((await brew(preGroundBrew)).grindRpm, isNull);

    // Turning RPM off later keeps the recorded history.
    await repository.updateGrinder(
      id: variableId,
      name: 'Variable grinder',
      hasAdjustableRpm: false,
    );
    expect((await brew(variableBrew)).grindRpm, 1200);

    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'Espresso',
        pressureBar: 45,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        bloomSeconds: 0,
      ),
      throwsArgumentError,
    );
  });
}
