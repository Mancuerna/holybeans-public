import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/journal_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late JournalRepository repository;

  setUpAll(() async {
    // Every database in this file uses its own in-memory SQLite executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('es');
  });

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('current schema has the inventory, freezer, water, extraction, favourite, photo, freshness, tasting, reminder and jug columns', () async {
    expect(database.schemaVersion, AppDatabase.currentSchema);
    final restColumns = await database
        .customSelect('PRAGMA table_info(coffees)')
        .get();
    expect(
      restColumns.map((row) => row.read<String>('name')),
      contains('rest_days'),
    );
    final pauseColumns = await database
        .customSelect('PRAGMA table_info(coffee_lots)')
        .get();
    expect(
      pauseColumns.map((row) => row.read<String>('name')),
      contains('frozen_pause_days'),
    );
    Future<Set<String>> columnsOf(String table) async => {
      for (final row
          in await database.customSelect('PRAGMA table_info($table)').get())
        row.read<String>('name'),
    };
    // Photos live in their own tables since schema 17.
    for (final table in ['coffees', 'brews']) {
      expect(await columnsOf(table), isNot(contains('photo_file')));
    }
    expect(await columnsOf('coffee_photos'), {
      'coffee_id',
      'position',
      'file_name',
    });
    expect(await columnsOf('brew_photos'), {
      'brew_id',
      'position',
      'file_name',
    });
    expect(await columnsOf('coffees'), containsAll({'is_decaf', 'shop_url'}));
    expect(await columnsOf('coffee_components'), contains('harvest'));
    expect(await columnsOf('brews'), contains('first_drip_seconds'));
    expect(
      await columnsOf('brew_methods'),
      containsAll({'vessel_name', 'vessel_grams', 'pour_plan_json'}),
    );
    expect(await columnsOf('app_preferences'), contains('last_backup_at_ms'));
    expect(
      await columnsOf('water_profiles'),
      containsAll({
        'calcium_ppm',
        'magnesium_ppm',
        'sodium_ppm',
        'potassium_ppm',
        'chloride_ppm',
        'sulfate_ppm',
      }),
    );
    final coffeeTasteColumns = await database
        .customSelect('PRAGMA table_info(coffees)')
        .get();
    expect(
      coffeeTasteColumns.map((row) => row.read<String>('name')),
      containsAll({'flavor_profile', 'is_favorite'}),
    );
    final grinderColumns = await database
        .customSelect('PRAGMA table_info(grinders)')
        .get();
    expect(
      grinderColumns.map((row) => row.read<String>('name')),
      contains('has_adjustable_rpm'),
    );
    final frozenColumns = await database
        .customSelect('PRAGMA table_info(frozen_portions)')
        .get();
    expect(
      frozenColumns.map((row) => row.read<String>('name')),
      containsAll({
        'lot_id',
        'label',
        'container',
        'frozen_date',
        'initial_grams',
        'remaining_grams',
        'thawed_at_ms',
      }),
    );
    final lotColumns = await database
        .customSelect('PRAGMA table_info(coffee_lots)')
        .get();
    final lotNames = lotColumns.map((row) => row.read<String>('name')).toSet();
    expect(
      lotNames,
      containsAll({'initial_grams', 'remaining_grams', 'overdraw_grams'}),
    );
    final coffeeColumns = await database
        .customSelect('PRAGMA table_info(coffees)')
        .get();
    expect(
      coffeeColumns.map((row) => row.read<String>('name')),
      containsAll({'rating', 'roast_level'}),
    );
    final brewColumns = await database
        .customSelect('PRAGMA table_info(brews)')
        .get();
    expect(
      brewColumns.map((row) => row.read<String>('name')),
      containsAll({
        'grind_rpm',
        'pressure_bar',
        'preinfusion_seconds',
        'bloom_seconds',
        'archived_by_coffee',
        'water_profile_id',
        'water_profile_name',
      }),
    );
    final waterColumns = await database
        .customSelect('PRAGMA table_info(water_profiles)')
        .get();
    expect(
      waterColumns.map((row) => row.read<String>('name')),
      containsAll({
        'id',
        'name',
        'gh_ppm_as_caco3',
        'kh_ppm_as_caco3',
        'tds_ppm',
        'ph',
        'notes',
        'archived_at_ms',
      }),
    );
  });

  test(
    'coffee and brew survive a backup round trip with their relations',
    () async {
      final coffeeId = await repository.createCoffeeWithComponents(
        name: ' Kieni ',
        roaster: ' Loma ',
        components: const [
          CoffeeComponentInput(
            country: 'Kenya',
            region: 'Kirinyaga',
            variety: 'SL28, SL34',
            process: 'Washed',
          ),
          CoffeeComponentInput(
            country: 'Colombia',
            region: 'Huila',
            variety: 'Caturra',
            process: 'Washed',
          ),
        ],
        roastDate: '2026-09-12',
        initialGrams: 250,
        paidPriceCents: 1250,
        roastLevel: 'medium',
      );
      final lot = await database.select(database.coffeeLots).getSingle();
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        lotId: lot.id,
        methodName: 'Espresso',
        doseGrams: 18,
        beverageGrams: 38,
        timeSeconds: 29,
        tdsPercent: 9.2,
        brewedAt: DateTime.utc(2026, 9, 26, 16),
      );
      await setRemainingGrams(database, repository, coffeeId, lot, 200);
      expect(
        brewExtractionYield(await database.select(database.brews).getSingle()),
        closeTo(19.42, 0.01),
      );

      await repository.setCoffeeArchived(coffeeId, archived: true);
      expect(await repository.watchCoffees().first, isEmpty);
      expect(
        await database.select(database.brews).getSingle(),
        isA<Brew>()
            .having((brew) => brew.id, 'id', brewId)
            .having((brew) => brew.archivedByCoffee, 'archivedByCoffee', true),
      );
      await repository.setCoffeeArchived(coffeeId, archived: false);
      expect((await repository.watchCoffees().first).single.name, 'Kieni');

      final source = await JournalBackup(database).exportJson();
      final preview = JournalBackup.inspectJson(source);
      expect(preview.coffees, 1);
      expect(preview.brews, 1);
      final decoded = jsonDecode(source) as Map<String, dynamic>;
      expect(decoded['format'], JournalBackup.format);
      expect(decoded['version'], JournalBackup.version);

      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      final summary = await JournalBackup(restored).restoreJson(source);
      expect(summary.coffees, 1);
      expect(summary.components, 2);
      expect(summary.lots, 1);
      expect(summary.brews, 1);
      expect(
        (await restored.select(restored.coffees).getSingle()).id,
        coffeeId,
      );
      expect(
        (await restored.select(restored.coffees).getSingle()).paidPriceCents,
        1250,
      );
      expect(
        (await restored.select(restored.coffees).getSingle()).roastLevel,
        'medium',
      );
      expect(
        (await restored.select(restored.coffeeLots).getSingle()).coffeeId,
        coffeeId,
      );
      final restoredLot = await restored
          .select(restored.coffeeLots)
          .getSingle();
      expect(restoredLot.remainingGrams, 200);
      expect((await restored.select(restored.brews).getSingle()).lotId, lot.id);
      final restoredComponents = await JournalRepository(restored)
          .coffeeComponents(coffeeId);
      expect(restoredComponents.map((component) => component.position), [0, 1]);
      expect(restoredComponents.map((component) => component.country), [
        'Kenya',
        'Colombia',
      ]);
      expect(restoredComponents.first.region, 'Kirinyaga');
      expect(restoredComponents.last.region, 'Huila');
    },
  );

  test('v5 backup without the new nullable fields remains readable', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Old backup coffee',
      roaster: 'Local',
      initialGrams: 100,
    );
    final lot = await database.select(database.coffeeLots).getSingle();
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'V60',
      doseGrams: 10,
    );
    final oldBackup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    final rows = oldBackup['data'] as Map<String, dynamic>;
    (rows['coffees'] as List).single.remove('rating');
    (rows['coffees'] as List).single.remove('roastLevel');
    (rows['lots'] as List).single.remove('overdrawGrams');
    (rows['brews'] as List).single.remove('waterProfileId');
    (rows['brews'] as List).single.remove('waterProfileName');
    (rows['brews'] as List).single.remove('archivedByCoffee');
    rows.remove('waterProfiles');

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    await JournalBackup(restored).restoreJson(jsonEncode(oldBackup));
    expect(
      (await restored.select(restored.coffees).getSingle()).rating,
      isNull,
    );
    expect(
      (await restored.select(restored.coffees).getSingle()).roastLevel,
      isNull,
    );
    final restoredLot = await restored.select(restored.coffeeLots).getSingle();
    expect(restoredLot.remainingGrams, 90);
    expect(restoredLot.overdrawGrams, isNull);
    expect(
      (await restored.select(restored.brews).getSingle()).archivedByCoffee,
      isNull,
    );
    final restoredBrew = await restored.select(restored.brews).getSingle();
    expect(restoredBrew.waterProfileId, isNull);
    expect(restoredBrew.waterProfileName, isNull);
    expect(await restored.select(restored.waterProfiles).get(), isEmpty);
  });

  test(
    'v5 backup roundtrips water links and validates them atomically',
    () async {
      final coffeeId = await repository.createCoffee(
        name: 'Water backup coffee',
        roaster: 'Local',
      );
      final profileId = await repository.createWaterProfile(
        name: 'Low mineral',
        ghPpmAsCaCO3: 45,
        khPpmAsCaCO3: 30,
        tdsPpm: 80,
        ph: 6.8,
        notes: 'Bottle water',
      );
      final brewId = await repository.createBrew(
        coffeeId: coffeeId,
        methodName: 'V60',
        waterProfileId: profileId,
      );
      await repository.setWaterProfileArchived(profileId, archived: true);

      final source = await JournalBackup(database).exportJson();
      expect(JournalBackup.inspectJson(source).waterProfiles, 1);
      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      await JournalBackup(restored).restoreJson(source);
      final restoredBrew = await (restored.select(
        restored.brews,
      )..where((brew) => brew.id.equals(brewId))).getSingle();
      expect(restoredBrew.waterProfileId, profileId);
      expect(restoredBrew.waterProfileName, 'Low mineral');
      final restoredProfile = await restored
          .select(restored.waterProfiles)
          .getSingle();
      expect(restoredProfile.archivedAtMs, isNotNull);
      expect(restoredProfile.ghPpmAsCaCO3, 45);
      expect(restoredProfile.khPpmAsCaCO3, 30);
      expect(restoredProfile.tdsPpm, 80);
      expect(restoredProfile.ph, 6.8);

      final existingCoffeeId = await JournalRepository(restored)
          .createCoffee(name: 'Keep this coffee', roaster: 'Local');
      final invalid = jsonDecode(source) as Map<String, dynamic>;
      final data = invalid['data'] as Map<String, dynamic>;
      ((data['brews'] as List).single
              as Map<String, dynamic>)['waterProfileId'] =
          'missing-profile';
      await expectLater(
        JournalBackup(restored).restoreJson(jsonEncode(invalid)),
        throwsFormatException,
      );
      expect(
        (await restored.select(restored.coffees).get()).map((row) => row.id),
        contains(existingCoffeeId),
      );
      expect(
        (await restored.select(restored.brews).getSingle()).waterProfileId,
        profileId,
      );
    },
  );

  test('invalid restore leaves existing records untouched', () async {
    final originalId = await repository.createCoffee(
      name: 'Existing',
      roaster: 'Local',
    );
    final sourceDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(sourceDatabase.close);
    final sourceRepository = JournalRepository(sourceDatabase);
    final otherId = await sourceRepository.createCoffee(
      name: 'Incoming',
      roaster: 'Loma',
    );
    await sourceRepository.createBrew(coffeeId: otherId, methodName: 'V60');
    final backup = jsonDecode(
      await JournalBackup(sourceDatabase).exportJson(),
    ) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;
    final brews = data['brews'] as List<dynamic>;
    (brews.single as Map<String, dynamic>)['coffeeId'] = 'missing-coffee';

    await expectLater(
      JournalBackup(database).restoreJson(jsonEncode(backup)),
      throwsA(isA<Exception>()),
    );
    final coffees = await database.select(database.coffees).get();
    expect(coffees.map((coffee) => coffee.id), [originalId]);
    expect(await database.select(database.brews).get(), isEmpty);
  });

  test('old backup versions and unknown fields are rejected', () async {
    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    backup['version'] = 4;
    await expectLater(
      JournalBackup(database).restoreJson(jsonEncode(backup)),
      throwsFormatException,
    );
    backup['version'] = 3;
    await expectLater(
      JournalBackup(database).restoreJson(jsonEncode(backup)),
      throwsFormatException,
    );
    backup['version'] = 5;
    (backup['data'] as Map<String, dynamic>)['futureRecords'] = <Object?>[];
    await expectLater(
      JournalBackup(database).restoreJson(jsonEncode(backup)),
      throwsFormatException,
    );
  });

  test('share fields survive a backup round trip', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Kieni',
      roaster: 'Loma',
      country: 'Kenya',
      initialGrams: 250,
      paidPriceCents: 2450,
    );
    final lot = await database.select(database.coffeeLots).getSingle();
    await repository.createBrew(
      coffeeId: coffeeId,
      lotId: lot.id,
      methodName: 'Espresso',
      doseGrams: 18,
      beverageGrams: 38,
      tdsPercent: 9.2,
      rating: 7.5,
      brewedAt: DateTime.utc(2026, 9, 26, 16),
    );
    const fields = {
      BrewParameter.coffee,
      BrewParameter.country,
      BrewParameter.method,
      BrewParameter.dose,
      BrewParameter.tds,
      BrewParameter.ey,
      BrewParameter.rating,
    };
    await BrewParameterSettings(database).saveShared(fields);
    final coffee = await database.select(database.coffees).getSingle();
    final component = await database
        .select(database.coffeeComponents)
        .getSingle();
    final brew = await database.select(database.brews).getSingle();
    final text = BrewShareText.build(
      strings: AppLocalizationsEs(),
      coffee: coffee,
      components: [component],
      brew: brew,
      fields: fields,
    );
    expect(text, contains('País: Kenya\n- - - - - - -\nMétodo: Espresso'));
    expect(text, contains('TDS: 9.2 %\nEY: 19.4 %'));
    expect(text, contains('Valoración: 7.5 / 10'));

    final source = await JournalBackup(database).exportJson();
    final backup = jsonDecode(source) as Map<String, dynamic>;
    expect(backup['version'], JournalBackup.version);
    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    await JournalBackup(restored).restoreJson(source);
    expect(await BrewParameterSettings(restored).loadShared(), fields);
    expect(
      (await restored.select(restored.coffees).getSingle()).paidPriceCents,
      2450,
    );
    final old = Map<String, dynamic>.from(backup)..['version'] = 4;
    await expectLater(
      JournalBackup(restored).restoreJson(jsonEncode(old)),
      throwsFormatException,
    );
    expect((await restored.select(restored.brews).get()).length, 1);
  });

  test('v5 backup roundtrips equipment, pre-ground brews and tools', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Kieni',
      roaster: 'Loma',
    );
    final methodId = await repository.createMethod(name: 'V60');
    final grinderId = await repository.createGrinder(name: 'Comandante C40');
    final toolId = await repository.createMethodTool(
      methodId: methodId,
      name: 'Paper filter',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      methodId: methodId,
      grinderName: 'Comandante C40',
      grinderId: grinderId,
      grindSetting: '22 clicks',
      methodToolIds: [toolId],
    );
    final preGroundBrewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      methodId: methodId,
      isPreGround: true,
      timeSeconds: 155,
    );
    final backup = await JournalBackup(database).exportJson();
    final preview = JournalBackup.inspectJson(backup);
    expect(preview.grinders, 1);
    expect(preview.methodTools, 1);
    expect(preview.brewToolSelections, 1);

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final summary = await JournalBackup(restored).restoreJson(backup);
    final brew = await (restored.select(
      restored.brews,
    )..where((row) => row.id.equals(brewId))).getSingle();
    expect(summary.grinders, 1);
    expect(summary.methodTools, 1);
    expect(summary.brewToolSelections, 1);
    expect(brew.id, brewId);
    expect(brew.methodId, methodId);
    expect(brew.methodName, 'V60');
    expect(brew.grinderName, 'Comandante C40');
    expect(brew.grinderId, grinderId);
    expect(brew.grindSetting, '22 clicks');
    final preGroundBrew = await (restored.select(
      restored.brews,
    )..where((row) => row.id.equals(preGroundBrewId))).getSingle();
    expect(preGroundBrew.isPreGround, isTrue);
    expect(preGroundBrew.grinderId, isNull);
    expect(preGroundBrew.grinderName, isNull);
    expect(preGroundBrew.grindSetting, isNull);
    expect(preGroundBrew.timeSeconds, 155);
    expect(
      (await restored.select(restored.methodTools).getSingle()).id,
      toolId,
    );
    expect(await JournalRepository(restored).brewToolIds(brewId), [toolId]);
  });

  test('older backups without grinder RPM still restore', () async {
    await repository.createGrinder(name: 'Old grinder');
    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    backup['version'] = 6;
    for (final grinder
        in (backup['data'] as Map<String, dynamic>)['grinders'] as List) {
      (grinder as Map<String, dynamic>).remove('hasAdjustableRpm');
    }
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(jsonEncode(backup));
    final restored = await target.select(target.grinders).getSingle();
    expect(restored.hasAdjustableRpm, isFalse);
  });
}
