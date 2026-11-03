import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/cupping.dart';

void main() {
  late AppDatabase db;
  late JournalRepository r;
  late String coffee;
  late String lot;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    r = JournalRepository(db);
    coffee = await r.createCoffee(
      name: 'Kenya',
      roaster: 'R',
      initialGrams: 100,
    );
    lot = (await r.coffeeLots(coffee)).single.id;
  });
  tearDown(() => db.close());
  CuppingDraft draft({int count = 2}) =>
      CuppingDraft(
          cups: [
            for (var i = 0; i < count; i++)
              CuppingCupDraft(coffeeId: coffee, lotId: lot)
                ..rating = i == 0 ? 0 : 8.5
                ..scores = [1, 2, 3, 4, 5],
          ],
        )
        ..startedAtMs = 1000
        ..brokenAtMs = 241000
        ..tastingAtMs = 721000
        ..phase = CuppingPhase.tasting;

  test(
    'drafts persist without creating methods, brews or consuming stock',
    () async {
      final d = draft();
      final id = await r.createCuppingSession(d);
      d.cups[0].notes = 'Saved draft';
      await r.saveCuppingDraft(id, d);
      expect(
        CuppingDraft.fromJson((await r.cuppingSession(id))!.draftJson)
            .cups[0]
            .notes,
        'Saved draft',
      );
      expect(await r.allBrews(), isEmpty);
      expect(await r.allMethods(), isEmpty);
      expect((await r.coffeeLot(lot))!.remainingGrams, 100);
      await r.discardCuppingDraft(id);
      expect(await r.cuppingSession(id), null);
    },
  );
  test(
    'repeated coffees consume each dose and finalising twice is idempotent',
    () async {
      final d = draft(count: 3);
      final id = await r.createCuppingSession(d);
      final ids = await r.finishCupping(id, d);
      expect(await r.finishCupping(id, d), ids);
      expect(await r.allBrews(), hasLength(3));
      expect((await r.coffeeLot(lot))!.remainingGrams, 67);
      final brews = await r.allBrews();
      expect(brews.map((b) => b.timeSeconds), everyElement(isNull));
      expect(brews.map((b) => b.methodName), everyElement('Cupping'));
      expect(brews.map((b) => b.acidity), everyElement(1));
      expect(brews.any((b) => b.rating == 0), true);
      expect((await r.cuppingCups(id)).map((c) => c.position), [0, 1, 2]);
      expect((await r.allMethods()).single.category, 'immersion');
      await r.discardCuppingDraft(id);
      expect(await r.cuppingSession(id), isNotNull);
      await expectLater(r.saveCuppingDraft(id, d), throwsStateError);
    },
  );
  test(
    'common equipment and explicit per-cup overrides save actual values',
    () async {
      final g = await r.createGrinder(name: 'Common');
      final g2 = await r.createGrinder(name: 'Other');
      final w = await r.createWaterProfile(name: 'Common water');
      final w2 = await r.createWaterProfile(name: 'Other water');
      final d = draft(count: 3)
        ..grinderId = g
        ..grindSetting = '20'
        ..waterProfileId = w;
      d.cups[1]
        ..commonGrinder = false
        ..grinderId = g2
        ..grindSetting = '30'
        ..commonWater = false
        ..waterProfileId = w2;
      d.cups[2]
        ..commonGrinder = false
        ..commonWater = false;
      final ids = await r.finishCupping(await r.createCuppingSession(d), d);
      final a = (await r.brew(ids[0]))!;
      final b = (await r.brew(ids[1]))!;
      final c = (await r.brew(ids[2]))!;
      expect((a.grinderId, a.grindSetting, a.waterProfileId), (g, '20', w));
      expect((b.grinderId, b.grindSetting, b.waterProfileId), (g2, '30', w2));
      expect((c.grinderId, c.waterProfileId), (null, null));
    },
  );
  test('aggregated shortage rejects the entire session', () async {
    final d = draft()..dose = 60;
    final id = await r.createCuppingSession(d);
    await expectLater(
      r.finishCupping(id, d),
      throwsA(isA<CuppingStockException>()),
    );
    expect(await r.allBrews(), isEmpty);
    expect(await r.allMethods(), isEmpty);
    expect((await r.coffeeLot(lot))!.remainingGrams, 100);
    expect((await r.cuppingSession(id))!.completedAtMs, null);
  });
  test(
    'failure on the last cup rolls back already-written brews and stock',
    () async {
      final d = draft(count: 3);
      d.cups.last
        ..commonGrinder = false
        ..grinderId = 'missing-grinder';
      final id = await r.createCuppingSession(d);
      await expectLater(r.finishCupping(id, d), throwsStateError);
      expect(await r.allBrews(), isEmpty);
      expect(await r.allMethods(), isEmpty);
      expect(await r.cuppingCups(id), isEmpty);
      expect((await r.coffeeLot(lot))!.remainingGrams, 100);
    },
  );
  test(
    'frozen cups thaw atomically and deleting restores their origin',
    () async {
      final portion = await r.freezeCoffee(
        lotId: lot,
        grams: 50,
        frozenDate: '2026-10-08',
      );
      final d = draft();
      for (final c in d.cups) {
        c.frozenPortionId = portion;
      }
      final id = await r.createCuppingSession(d);
      final ids = await r.finishCupping(id, d);
      expect((await r.frozenPortionsForLot(lot)).single.remainingGrams, 28);
      expect((await r.coffeeLot(lot))!.remainingGrams, 50);
      await r.deleteBrew(ids.first);
      expect((await r.frozenPortionsForLot(lot)).single.remainingGrams, 39);
      expect((await r.cuppingCups(id)).single.position, 1);
      final exported = await JournalBackup(db).exportJson();
      await JournalBackup(db).restoreJson(exported);
      expect((await r.cuppingCups(id)).single.position, 1);
    },
  );
  test('draft and finished sessions survive the backup round trip', () async {
    final d = draft();
    final unfinished = await r.createCuppingSession(CuppingDraft());
    final finished = await r.createCuppingSession(d);
    await r.finishCupping(finished, d);
    final json = await JournalBackup(db).exportJson();
    expect(jsonDecode(json)['version'], JournalBackup.version);
    expect(JournalBackup.inspectJson(json).cuppingSessions, 2);
    await JournalBackup(db).restoreJson(json);
    expect((await r.cuppingSession(unfinished))!.completedAtMs, null);
    expect((await r.cuppingSession(finished))!.completedAtMs, isNotNull);
    expect(await r.cuppingCups(finished), hasLength(2));
    final again = jsonDecode(await JournalBackup(db).exportJson())['data'];
    expect(again, jsonDecode(json)['data']);
  });
  test('malformed cupping backup fails before replacing the journal', () async {
    final d = draft();
    final id = await r.createCuppingSession(d);
    await r.finishCupping(id, d);
    final before = await JournalBackup(db).exportJson();
    final map = jsonDecode(before);
    map['data']['cuppingSessionCups'][0]['position'] = 9;
    await expectLater(
      JournalBackup(db).restoreJson(jsonEncode(map)),
      throwsFormatException,
    );
    expect(
      jsonDecode(await JournalBackup(db).exportJson())['data'],
      jsonDecode(before)['data'],
    );
  });
  test('old backups clear sessions and keep their existing brews', () async {
    final d = draft();
    final id = await r.createCuppingSession(d);
    await r.finishCupping(id, d);
    final map = jsonDecode(await JournalBackup(db).exportJson());
    map['version'] = 26;
    map['data'].remove('cuppingSessions');
    map['data'].remove('cuppingSessionCups');
    await JournalBackup(db).restoreJson(jsonEncode(map));
    expect(await r.cuppingSession(id), null);
    expect(await r.allBrews(), hasLength(2));
  });
}
