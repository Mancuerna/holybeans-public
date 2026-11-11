import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';

import 'helpers/blind_cupping_fixture.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy drafts default to normal cupping', () {
    final map = jsonDecode(CuppingDraft().toJson()) as Map<String, dynamic>
      ..remove('blind')
      ..remove('revealed');
    final d = CuppingDraft.fromJson(jsonEncode(map));
    expect(d.blind, false);
    expect(d.revealed, false);
  });

  test(
    'anonymous six-cup ratings survive roundtrip but need identification',
    () {
      final d = CuppingDraft.fromJson(blindTasting(count: 6).toJson());
      expect(d.canReveal, true);
      expect(d.ready, false);
      expect(d.cups.map((c) => c.coffeeId), everyElement(isNull));
      expect(d.cups.first.rating, 0);
      d.cups.last.scores[4] = null;
      expect(d.canReveal, false);
    },
  );

  for (final (label, mutate) in <(String, void Function(CuppingDraft))>[
    ('hidden coffee', (d) => d.cups[0].coffeeId = 'c'),
    ('hidden lot', (d) => d.cups[0].lotId = 'l'),
    ('hidden portion', (d) => d.cups[0].frozenPortionId = 'p'),
    ('unconfirmed review', (d) => d.phase = CuppingPhase.review),
    ('premature reveal', (d) => d.revealed = true),
    (
      'incomplete reveal',
      (d) {
        d.revealed = true;
        d.phase = CuppingPhase.review;
        d.cups.last.rating = null;
      },
    ),
  ]) {
    test('rejects invalid blind draft: $label', () {
      final d = blindTasting();
      mutate(d);
      expect(() => CuppingDraft.fromJson(d.toJson()), throwsFormatException);
    });
  }

  group('blind session persistence and inventory', () {
    late AppDatabase db;
    late JournalRepository r;
    late String coffee;
    late String lot;
    setUp(() async {
      db = memoryDatabase();
      r = JournalRepository(db);
      coffee = await r.createCoffee(
        name: 'Secret Kenya',
        roaster: 'R',
        initialGrams: 100,
      );
      lot = (await r.coffeeLots(coffee)).single.id;
    });
    tearDown(() => db.close());

    Future<CuppingModel> model(CuppingDraft d) async {
      final id = await r.createCuppingSession(d);
      final m = CuppingModel(
        r,
        (await r.cuppingSession(id))!,
        d,
        clock: () => 1000,
      );
      await m.loadCatalogs();
      return m;
    }

    test(
      'timer pause and reset survive saving without moving the pour',
      () async {
        var now = 1000;
        final d = CuppingDraft()
          ..blind = true
          ..sound = false;
        final id = await r.createCuppingSession(d);
        final m = CuppingModel(
          r,
          (await r.cuppingSession(id))!,
          d,
          clock: () => now,
        );
        await m.loadCatalogs();
        expect(await m.start(), true);
        now = 121000;
        m.toggleClock();
        now = 201000;
        expect(m.elapsed, 120);
        await m.flush();
        expect(
          CuppingDraft.fromJson((await r.cuppingSession(id))!.draftJson)
              .elapsedAt(now),
          120,
        );
        m.toggleClock();
        now = 202000;
        expect(m.elapsed, 121);
        m.resetClock();
        expect(m.elapsed, 0);
        expect(d.startedAtMs, 1000);
        await m.flush();
        expect(
          CuppingDraft.fromJson((await r.cuppingSession(id))!.draftJson)
              .elapsedAt(now),
          0,
        );
        m.dispose();
      },
    );

    test(
      'starts without coffees and resumes anonymously without consumption',
      () async {
        final d = CuppingDraft()
          ..blind = true
          ..sound = false;
        final m = await model(d);
        expect(m.canStart, true);
        expect(await m.start(), true);
        m.chooseCoffee(d.cups.first, coffee);
        expect(d.cups.first.coffeeId, null);
        await m.flush();
        final resumed = CuppingDraft.fromJson(
          (await r.cuppingSession(m.session.id))!.draftJson,
        );
        expect(resumed.blind, true);
        expect(resumed.phase, CuppingPhase.infusion);
        expect(resumed.cups.map((c) => c.coffeeId), everyElement(isNull));
        expect(await r.allBrews(), isEmpty);
        expect((await r.coffeeLot(lot))!.remainingGrams, 100);
        m.dispose();
      },
    );

    test(
      'reveal needs complete scores and locks results across save and finish',
      () async {
        final d = blindTasting()..cups.last.scores[4] = null;
        final m = await model(d);
        expect(await m.reveal(), false);
        m.change(() => d.cups.last.scores[4] = 5);
        expect(await m.reveal(), true);
        final stored = (await r.cuppingSession(m.session.id))!.draftJson;
        for (final cup in d.cups) {
          m.chooseCoffee(cup, coffee);
        }
        await m.flush();
        expect(m.scoresLocked, true);
        final changed = CuppingDraft.fromJson(d.toJson())
          ..cups.first.rating = 10;
        await expectLater(
          r.saveCuppingDraft(m.session.id, changed),
          throwsStateError,
        );
        await expectLater(
          r.finishCupping(m.session.id, changed),
          throwsStateError,
        );
        final notes = CuppingDraft.fromJson(d.toJson())
          ..cups.first.notes = 'after reveal';
        await expectLater(
          r.saveCuppingDraft(m.session.id, notes),
          throwsStateError,
        );
        expect(CuppingDraft.fromJson(stored).cups.first.rating, 0);
        expect(await r.allBrews(), isEmpty);
        expect(await m.finish(), true);
        expect((await r.allBrews()).map((b) => b.rating), contains(0));
        m.dispose();
      },
    );

    test(
      'partial identification survives backup and keeps fixed notes',
      () async {
        final m = await model(blindTasting());
        expect(await m.reveal(), true);
        m.chooseCoffee(m.draft.cups.first, coffee);
        await m.flush();
        expect(await m.finish(), false);
        final backup = await JournalBackup(db).exportJson();
        await JournalBackup(db).restoreJson(backup);
        final restored = CuppingDraft.fromJson(
          (await r.cuppingSession(m.session.id))!.draftJson,
        );
        expect(restored.revealed, true);
        expect(restored.cups.first.coffeeId, coffee);
        expect(restored.cups.last.coffeeId, null);
        expect(restored.cups.last.notes, 'Cup B notes');
        expect(await r.allBrews(), isEmpty);
        expect((await r.coffeeLot(lot))!.remainingGrams, 100);
        m.dispose();
      },
    );

    test(
      'combined shortage keeps the whole draft and permits reassigning a cup',
      () async {
        final m = await model(blindTasting()..dose = 60);
        await m.reveal();
        for (final cup in m.draft.cups) {
          m.chooseCoffee(cup, coffee);
        }
        expect(await m.finish(), false);
        expect(m.error, isA<CuppingStockException>());
        expect(await r.allBrews(), isEmpty);
        expect((await r.coffeeLot(lot))!.remainingGrams, 100);
        final other = await r.createCoffee(
          name: 'Other',
          roaster: 'R',
          initialGrams: 100,
        );
        await m.loadCatalogs();
        m.chooseCoffee(m.draft.cups.last, other);
        expect(await m.finish(), true);
        expect((await r.coffeeLot(lot))!.remainingGrams, 40);
        expect(
          (await r.allBrews()).map((b) => b.notes),
          containsAll(['Cup A notes', 'Cup B notes']),
        );
        m.dispose();
      },
    );

    test('repeated coffee with fresh and frozen sources saves once and restores origin', () async {
      final portion = await r.freezeCoffee(
        lotId: lot,
        grams: 50,
        frozenDate: '2026-10-09',
      );
      final m = await model(blindTasting());
      await m.reveal();
      for (final cup in m.draft.cups) {
        m.chooseCoffee(cup, coffee);
      }
      m.change(() => m.draft.cups.last.frozenPortionId = portion);
      expect(await m.finish(), true);
      final links = await r.cuppingCups(m.session.id);
      expect(
        await r.finishCupping(m.session.id, m.draft),
        links.map((c) => c.brewId).toList(),
      );
      expect((await r.coffeeLot(lot))!.remainingGrams, 39);
      expect((await r.frozenPortionsForLot(lot)).single.remainingGrams, 39);
      final shared = await r.cuppingShareData(m.session.id);
      expect(shared.blind, true);
      expect(shared.cups.map((c) => c.letter), ['A', 'B']);
      expect(shared.cups.first.brew!.rating, 0);
      await r.deleteBrew(links.last.brewId);
      expect((await r.frozenPortionsForLot(lot)).single.remainingGrams, 50);
      m.dispose();
    });

    test('cannot change mode after the clock starts or finish without confirmed reveal', () async {
      final m = await model(
        CuppingDraft()
          ..blind = true
          ..sound = false,
      );
      await m.start();
      m.setBlind(false);
      expect(m.draft.blind, true);
      final changed = CuppingDraft.fromJson(m.draft.toJson())..blind = false;
      await expectLater(
        r.saveCuppingDraft(m.session.id, changed),
        throwsStateError,
      );
      final fabricated = blindTasting()
        ..revealed = true
        ..phase = CuppingPhase.review;
      for (final c in fabricated.cups) {
        c.coffeeId = coffee;
        c.lotId = lot;
      }
      await expectLater(
        r.finishCupping(m.session.id, fabricated),
        throwsStateError,
      );
      expect(await r.allBrews(), isEmpty);
      m.dispose();
    });
  });
}
