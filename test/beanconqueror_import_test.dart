import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/domain/beanconqueror/bq_flow_profile.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/test_database.dart';

void main() {
  test('BeanConqueror values become HolyBeans ones', () {
    expect(bqRating(2.5, 5), 5);
    expect(bqRating(3.7, 5), 7.5);
    expect(bqRating(0, 5), isNull, reason: '0 is not rated');
    expect(bqRating(-1, 5), isNull);
    expect(bqRating(8, 10), 8);
    expect(bqAltitude('1.900 msnm'), 1900);
    expect(bqAltitude('1800-2000 m'), 1800);
    expect(bqAltitude('1400'), 1400);
    expect(bqAltitude('alta'), isNull);
    expect(bqPositive(0), isNull);
    expect(bqText('  '), isNull);
    expect(bqSeconds(28, 400), 28);
    expect(bqRoastLevel('CINNAMON_ROAST'), 'light');
    expect(bqRoastLevel('UNKNOWN'), isNull);
    expect(bqMethodCategory('FULL_IMMERSION'), 'immersion');
    expect(bqContainer('VACUUM_SEALED'), 'vacuum_bag');
    expect(bqFileName('/beans/photo_1.jpg'), 'photo_1.jpg');
    // 100 ppm as CaCO3 of calcium is 40 mg/l of calcium ions.
    expect(bqIonPpm(100, 'PPM', molarMass: 40.078), closeTo(40.04, 0.01));
    expect(bqIonPpm(1, 'MMOL_L', molarMass: 22.99, charge: 1), 22.99);
    expect(bqHardnessPpm(5, 'DH'), closeTo(89.25, 0.01));
  });

  test('the ZIP is read with its chunks, and other files are refused', () {
    final export = BeanconquerorArchive.read(zip());
    expect(export.beans, hasLength(2));
    expect(export.brews, hasLength(3), reason: 'main file plus chunk 1');
    expect(export.preparations, hasLength(2));
    expect(export.settings['brew_rating'], 5);

    final plain = BeanconquerorArchive.read(
      Uint8List.fromList(utf8.encode(jsonEncode(exportJson()))),
    );
    expect(plain.brews, hasLength(1));

    expect(
      () => BeanconquerorArchive.read(Uint8List.fromList(utf8.encode('{}'))),
      throwsA(isA<BqArchiveException>()),
    );
    final noMain = Archive()..add(ArchiveFile.bytes('other.json', [1]));
    expect(
      () => BeanconquerorArchive.read(
        Uint8List.fromList(ZipEncoder().encode(noMain)),
      ),
      throwsA(isA<BqArchiveException>()),
    );
  });

  test('a ZIP of the export folder brings its curves and photos', () {
    final bytes = folderZip();
    final export = BeanconquerorArchive.read(bytes);
    expect(export.brews, hasLength(3), reason: 'read from the inner ZIP');
    expect(BeanconquerorArchive.extraFileNames(bytes), {
      'brew-v60_flow_profile.json',
      'unrelated_flow_profile.json',
      'photo_abc.jpg',
    });
    expect(BeanconquerorArchive.extraFileNames(zip()), isEmpty);
    final curves = BeanconquerorArchive.curves((
      bytes,
      {'brew-v60_flow_profile.json', 'unrelated_flow_profile.json', 'gone'},
    ));
    expect(curves.keys, [
      'brew-v60_flow_profile.json',
    ], reason: 'one that does not read is left out');
    expect(
      BeanconquerorArchive.files((bytes, {'photo_abc.jpg'}))['photo_abc.jpg'],
      [0xFF, 0xD8, 0xFF],
    );
  });

  test('an import adds everything once and keeps the originals', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    // The journal already has a V60: the import reuses it.
    final v60 = await repository.createMethod(
      name: 'v60 ',
      category: 'pourover',
    );

    final export = BeanconquerorArchive.read(zip());
    final plan = planBeanconquerorImport(
      export,
      await repository.beanconquerorJournal(),
      now: DateTime.utc(2026),
    );
    expect(plan.warnings[BqWarning.brewWithoutBean], 1);
    expect(plan.photoNames, {'photo_abc.jpg'});
    expect(plan.curveNames, {'brew-v60_flow_profile.json'});
    final summary = await repository.importBeanconqueror(
      plan,
      photos: {'photo_abc.jpg': '00000000-0000-4000-8000-000000000001.jpg'},
      curves: {'brew-v60_flow_profile.json': bqFlowCurve(v60FlowProfile())!},
    );
    expect(summary.curves, 1);
    expect(summary.coffees, 2);
    expect(summary.brews, 2);
    expect(summary.methods, 1, reason: 'the V60 is reused');
    expect(summary.photos, 1);

    final coffees = {
      for (final coffee in await database.select(database.coffees).get())
        coffee.name: coffee,
    };
    final finished = coffees['Finca Finished']!;
    expect(finished.roaster, 'Roast Club');
    expect(finished.rating, 8);
    expect(finished.paidPriceCents, 1350);
    expect(finished.roastLevel, 'medium');
    expect(finished.flavorProfile, 'Miel, fruta de hueso');
    expect(
      finished.archivedAtMs,
      DateTime(2025, 1, 5, 8).millisecondsSinceEpoch,
    );
    final origin = await (database.select(
      database.coffeeComponents,
    )..where((row) => row.coffeeId.equals(finished.id))).getSingle();
    expect(
      (origin.country, origin.producer, origin.altitudeMeters),
      ('Ethiopia', 'Khalid', 1900),
    );

    final lots = {
      for (final lot in await database.select(database.coffeeLots).get())
        lot.coffeeId: lot,
    };
    expect(lots[finished.id]!.remainingGrams, 0);
    expect(lots[finished.id]!.roastDate, '2025-01-01');
    final frozen = coffees['Frozen Gesha']!;
    expect(frozen.rating, isNull);
    expect(lots[frozen.id]!.remainingGrams, 0, reason: 'all in the freezer');
    final portion = await database.select(database.frozenPortions).getSingle();
    expect(
      (portion.label, portion.container, portion.remainingGrams),
      ('eb2a8c', 'tube', 85),
    );

    final brews = {
      for (final brew in await database.select(database.brews).get())
        brew.methodName: brew,
    };
    final shot = brews['Lelit Bianca']!;
    expect(shot.doseGrams, 18);
    expect(shot.waterGrams, isNull);
    expect(shot.beverageGrams, 36.4);
    expect(shot.preinfusionSeconds, 6);
    expect(shot.firstDripSeconds, 9);
    expect(shot.bloomSeconds, isNull);
    expect(shot.rating, 7);
    expect(shot.grinderName, 'Lagom 01');
    final machine = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(shot.methodId!))).getSingle();
    expect(
      (machine.machine, machine.machineAddress),
      ('meticulous', 'http://192.0.2.90'),
    );
    expect(shot.archivedAtMs, finished.archivedAtMs);
    expect(shot.archivedByCoffee, isTrue);
    expect(await repository.brewToolIds(shot.id), hasLength(1));
    // The reused method's name here ("v60") is kept, not BeanConqueror's.
    final pour = brews['v60']!;
    expect(pour.methodId, v60);
    expect(pour.bloomSeconds, 40);
    expect(pour.waterGrams, 250);
    expect(pour.beverageGrams, isNull);
    expect(pour.archivedAtMs, isNull);
    expect(pour.lotId, lots[frozen.id]!.id);
    final recorded = (await repository.brewCurve(pour.id))!;
    expect(recorded.source, 'beanconqueror');
    expect(recorded.curve.weight, [0, 3, 9]);
    expect(
      (await database.select(database.coffeePhotos).getSingle()).fileName,
      '00000000-0000-4000-8000-000000000001.jpg',
    );

    // Each record keeps its BeanConqueror ID and original JSON.
    final records = await database.select(database.importRecords).get();
    expect(records.where((row) => row.kind == BqKind.brew), hasLength(2));
    final payloads = await database.select(database.legacyPayloads).get();
    expect(payloads, hasLength(records.length));
    expect(payloads.any((row) => row.rawJson.contains('VST 18')), isTrue);

    // A second import of the same file adds nothing.
    final again = planBeanconquerorImport(
      export,
      await repository.beanconquerorJournal(),
      now: DateTime.utc(2026),
    );
    expect(again.isEmpty, isTrue);
    expect(again.skipped[BqKind.brew], 2);
    expect(again.skipped[BqKind.bean], 2);

    // Photos added in BeanConqueror later reach records without photos;
    // the bean that has one here keeps it.
    final json = exportJson();
    (json['BEANS'] as List).first['attachments'] = ['/photo_new_bean.jpg'];
    (json['BREWS'] as List).first['attachments'] = ['/photo_shot.jpg'];
    (json['BREWS'] as List).first['flow_profile'] =
        'brews/brew-espresso_flow_profile.json';
    final withPhotos = planBeanconquerorImport(
      BeanconquerorArchive.read(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      ),
      await repository.beanconquerorJournal(),
      now: DateTime.utc(2026),
    );
    expect(withPhotos.isEmpty, isFalse);
    // The bean has a photo here already, so only the brew's is asked for.
    expect(withPhotos.photoNames, {'photo_shot.jpg'});
    // The V60 brew has its curve already; the shot gains one.
    expect(withPhotos.curveNames, {'brew-espresso_flow_profile.json'});
    final photoSummary = await repository.importBeanconqueror(
      withPhotos,
      photos: {
        'photo_new_bean.jpg': '00000000-0000-4000-8000-000000000002.jpg',
        'photo_shot.jpg': '00000000-0000-4000-8000-000000000003.jpg',
      },
      curves: {
        'brew-espresso_flow_profile.json': bqFlowCurve(v60FlowProfile())!,
      },
    );
    expect(photoSummary.curves, 1);
    expect(await repository.brewCurve(shot.id), isNotNull);
    expect(photoSummary.photos, 1);
    expect(await repository.brewPhotos(shot.id), [
      '00000000-0000-4000-8000-000000000003.jpg',
    ]);
    expect(await repository.coffeePhotos(finished.id), [
      '00000000-0000-4000-8000-000000000001.jpg',
    ]);
  });

  test('changes in BeanConqueror update what was not edited here', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    await repository.importBeanconqueror(
      planBeanconquerorImport(
        BeanconquerorArchive.read(zip()),
        await repository.beanconquerorJournal(),
        now: DateTime.utc(2026),
      ),
    );
    Future<Brew> brew(String method) async =>
        (await database.select(database.brews).get()).firstWhere(
          (row) => row.methodName == method,
        );
    // The finished coffee gets a heart here, which is not an edit.
    final finished = await (database.select(
      database.coffees,
    )..where((row) => row.name.equals('Finca Finished'))).getSingle();
    await repository.setCoffeeFavorite(finished.id, favorite: true);
    // The V60 brew is edited here after the import.
    final pour = await brew('V60');
    await (database.update(
      database.brews,
    )..where((row) => row.id.equals(pour.id))).write(
      BrewsCompanion(
        notes: const Value('Edited here'),
        updatedAtMs: Value(pour.updatedAtMs + 60000),
      ),
    );

    // In BeanConqueror, the shot moves to today with a longer yield, the
    // finished bean is back in use under a new name and the V60 brew
    // changes too.
    final json = exportJson();
    final shot = (json['BREWS'] as List).first as Map<String, dynamic>;
    shot
      ..['config'] = config('brew-espresso', DateTime(2026, 10, 2, 6, 13))
      ..['brew_beverage_quantity'] = 42.9
      ..['rating'] = 5;
    final bean = (json['BEANS'] as List).first as Map<String, dynamic>;
    bean
      ..['name'] = 'Finca Renamed'
      ..['finished'] = false;
    final changedChunk = chunkBrews();
    changedChunk.first['note'] = 'Changed there';
    final archive = Archive()
      ..add(
        ArchiveFile.bytes('Beanconqueror.json', utf8.encode(jsonEncode(json))),
      )
      ..add(
        ArchiveFile.bytes(
          'Beanconqueror_Brews_1.json',
          utf8.encode(jsonEncode(changedChunk)),
        ),
      );
    final plan = planBeanconquerorImport(
      BeanconquerorArchive.read(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      ),
      await repository.beanconquerorJournal(),
      now: DateTime.utc(2026),
    );
    expect(plan.changedBrews, hasLength(1));
    expect(plan.changedCoffees, hasLength(1));
    expect(plan.conflicts, 1);
    // The V60 brew stays as edited here but still gets the curve it lacks.
    expect(plan.curveNames, contains('brew-v60_flow_profile.json'));

    final summary = await repository.importBeanconqueror(
      plan,
      curves: {'brew-v60_flow_profile.json': bqFlowCurve(v60FlowProfile())!},
    );
    expect(summary.updated, 2);
    expect(await repository.brewCurve((await brew('V60')).id), isNotNull);
    final updated = await brew('Lelit Bianca');
    expect(updated.beverageGrams, 42.9);
    expect(updated.rating, 10);
    expect(
      updated.brewedAtMs,
      DateTime(2026, 10, 2, 6, 13).millisecondsSinceEpoch,
    );
    // Back in use: the coffee and its brew are no longer archived.
    expect(updated.archivedAtMs, isNull);
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(updated.coffeeId))).getSingle();
    expect((coffee.name, coffee.archivedAtMs), ('Finca Renamed', null));
    expect(coffee.isFavorite, isTrue, reason: 'the heart set here stays');
    expect((await brew('V60')).notes, 'Edited here');

    // No change is left to bring over, only the conflict (and the bean's
    // photo, not picked in this import).
    final again = planBeanconquerorImport(
      BeanconquerorArchive.read(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      ),
      await repository.beanconquerorJournal(),
      now: DateTime.utc(2026),
    );
    expect(again.changedBrews, isEmpty);
    expect(again.changedCoffees, isEmpty);
    expect(again.conflicts, 1);
    expect(again.photoNames, {'photo_abc.jpg'});
  });
}
