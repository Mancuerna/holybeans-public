import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';

import 'helpers/ui_test_support.dart';

/// A bloom of 50 g, a 25 s rest and a pour of 200 g, every 100 ms.
ShotCurve bloomAndPour() {
  final times = <int>[];
  final weight = <double>[];
  var grams = 0.0;
  void add(int tenths, double Function(int) at) {
    for (var i = 1; i <= tenths; i++) {
      times.add(times.isEmpty ? 0 : times.last + 100);
      weight.add(at(i));
    }
  }

  add(20, (_) => 0);
  add(60, (i) => grams + 50 * i / 60);
  grams = 50;
  add(250, (_) => grams);
  add(100, (i) => grams + 200 * i / 100);
  grams = 250;
  add(100, (_) => grams);
  return ShotCurve(timesMs: times, flow: const [], weight: weight);
}

void main() {
  late AppDatabase database;
  late BrewFormModel model;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = JournalRepository(database);
    await repository.createCoffee(name: 'Kenya', roaster: 'R');
    model = BrewFormModel(
      repository: repository,
      settings: BrewParameterSettings(database),
      coffees: await database.select(database.coffees).get(),
    );
    model.draft.dose.text = '15';
  });

  tearDown(() async {
    model.dispose();
    await database.close();
  });

  test('stopping with a curve fills blank blooms and pours', () {
    model.fillPoursFromCurve(bloomAndPour());
    final pours = model.draft.pours;
    expect((pours.bloomCount, pours.pourCount), (1, 1));
    expect(pours.fromCurve, isTrue);
    expect(pours.detailsExpanded, isFalse);
    final bloom = pours.value.phases.first;
    expect(
      (bloom.waterGrams, bloom.durationSeconds, bloom.restSeconds),
      (50, 6, 25),
    );
    // The bloom total: pouring and resting.
    expect(model.draft.bloom.text, '31');

    pours.undoFromCurve();
    expect((pours.bloomCount, pours.pourCount), (null, null));
    expect(pours.value.phases, isEmpty);
    expect(model.draft.bloom.text, isEmpty);
  });

  test('automatic detection preserves details opened by the user', () {
    model.draft.pours.detailsExpanded = true;
    model.fillPoursFromCurve(bloomAndPour());
    expect(model.draft.pours.fromCurve, isTrue);
    expect(model.draft.pours.detailsExpanded, isTrue);
  });

  for (final (blooms, count, expected) in <(int?, int, (int, int))>[
    (null, 2, (0, 2)),
    (0, 2, (0, 2)),
    (1, 1, (1, 1)),
  ]) {
    test(
      'explicit counts $blooms + $count fill details and undo restores them',
      () {
        final pours = model.draft.pours
          ..setCount(BrewPourKind.bloom, blooms)
          ..setCount(BrewPourKind.pour, count);
        model.fillPoursFromCurve(bloomAndPour());
        expect((pours.bloomCount, pours.pourCount), expected);
        expect(pours.value.phases.map((p) => p.waterGrams), [50, 200]);
        expect(pours.fromCurve, isTrue);
        pours.undoFromCurve();
        expect((pours.bloomCount, pours.pourCount), (blooms, count));
        expect(pours.value.phases, isEmpty);
        expect(pours.curvePourCount, count);
        model.fillPoursFromCurve(bloomAndPour());
        expect(pours.fromCurve, isTrue);
      },
    );
  }

  test('compatible counts never replace manual phase details', () {
    final pours = model.draft.pours
      ..setCount(BrewPourKind.bloom, 0)
      ..setCount(BrewPourKind.pour, 2);
    pours.phaseDraft(BrewPourKind.pour, 1).water.text = '42';
    model.fillPoursFromCurve(bloomAndPour());
    expect(pours.fromCurve, isFalse);
    expect(pours.value.phases.single.waterGrams, 42);
  });

  test('incompatible explicit counts leave fields and bloom time intact', () {
    final pours = model.draft.pours
      ..setCount(BrewPourKind.bloom, 0)
      ..setCount(BrewPourKind.pour, 1);
    model.draft.bloom.text = '60';
    model.fillPoursFromCurve(bloomAndPour());
    expect((pours.bloomCount, pours.pourCount), (0, 1));
    expect(pours.fromCurve, isFalse);
    expect(pours.value.phases, isEmpty);
    expect(model.draft.bloom.text, '60');
  });

  test(
    'the measured bloom total replaces manual time and undo restores it',
    () {
      model.draft.bloom.text = '60';
      model.fillPoursFromCurve(bloomAndPour());
      expect(model.draft.pours.bloomCount, 1);
      expect(model.draft.bloom.text, '31');
      model.draft.pours.undoFromCurve();
      expect(model.draft.bloom.text, '60');
    },
  );

  test(
    'a manual total entered after detection survives another timer stop',
    () {
      model.fillPoursFromCurve(bloomAndPour());
      expect(model.draft.bloom.text, '31');
      model.draft.bloom.text = '40';
      model.fillPoursFromCurve(bloomAndPour());
      expect(model.draft.bloom.text, '40');
      expect(model.draft.pours.value.phases.first.restSeconds, 25);
    },
  );

  test(
    'detecting no blooms clears the previous total and undo restores it',
    () {
      model.draft.bloom.text = '60';
      model.draft.pours.setCount(BrewPourKind.bloom, 0);
      model.fillPoursFromCurve(bloomAndPour());
      expect(model.draft.bloom.text, isEmpty);
      model.draft.pours.undoFromCurve();
      expect(model.draft.bloom.text, '60');
    },
  );

  test(
    'two measured blooms replace a stale total in the form and storage',
    () async {
      final measured = brewPoursOf(const [
        DetectedPour(startMs: 0, endMs: 3000, grams: 26.6),
        DetectedPour(startMs: 44000, endMs: 48000, grams: 25.7),
        DetectedPour(startMs: 89000, endMs: 93000, grams: 49.6),
      ], bloomCount: 2)!;
      model.draft.bloom.text = '58';
      model.draft.pours.fillFromCurve(measured, bloomTotal: model.draft.bloom);
      expect(model.draft.bloom.text, '89');
      model.draft.pours.undoFromCurve();
      expect(model.draft.bloom.text, '58');

      final repository = JournalRepository(database);
      final coffee = (await repository.allCoffees()).single.id;
      final id = await repository.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        bloomSeconds: 58,
      );
      await repository.setBrewPours(id, measured);
      expect((await repository.brew(id))!.bloomSeconds, 89);

      await repository.saveBrew(
        id: id,
        coffeeId: coffee,
        methodName: 'V60',
        bloomSeconds: 60,
        pours: measured,
      );
      final edited = (await repository.brew(id))!;
      expect(edited.bloomSeconds, 60);
      expect(edited.pourPhasesJson, measured.phasesJson);
    },
  );

  test('what was written by hand is kept', () {
    final pours = model.draft.pours..setCount(BrewPourKind.pour, 3);
    model.fillPoursFromCurve(bloomAndPour());
    expect((pours.bloomCount, pours.pourCount), (null, 3));
    expect(pours.fromCurve, isFalse);

    // Only the number of blooms: the curve fills the rest around it.
    pours
      ..setCount(BrewPourKind.pour, null)
      ..setCount(BrewPourKind.bloom, 0);
    model.fillPoursFromCurve(bloomAndPour());
    expect((pours.bloomCount, pours.pourCount), (0, 2));
    pours.undoFromCurve();
    expect((pours.bloomCount, pours.pourCount), (0, null));

    model.fillPoursFromCurve(null);
    expect(pours.fromCurve, isFalse);
  });

  test('counts copied from a repeated brew take the details, and the '
      'count, from the curve', () async {
    final repository = JournalRepository(database);
    final coffee = (await repository.allCoffees()).single;
    final id = await repository.createBrew(
      coffeeId: coffee.id,
      methodName: 'V60',
      bloomSeconds: 58,
      pours: BrewPours(bloomCount: 1, pourCount: 3),
    );
    final repeated = BrewFormModel(
      repository: repository,
      settings: BrewParameterSettings(database),
      coffees: [coffee],
      seed: await repository.brew(id),
      repeat: true,
    );
    addTearDown(repeated.dispose);
    final pours = repeated.draft.pours;
    expect((pours.bloomCount, pours.pourCount), (1, 3));
    expect(repeated.draft.bloom.text, '58');
    repeated.fillPoursFromCurve(bloomAndPour());
    expect((pours.bloomCount, pours.pourCount), (1, 1));
    expect(repeated.draft.bloom.text, '31');
    expect(pours.value.phases.first.waterGrams, 50);
    pours.undoFromCurve();
    expect((pours.bloomCount, pours.pourCount), (1, 3));
    expect(repeated.draft.bloom.text, '58');
  });

  testWidgets('the section says where they came from and can undo it', (
    tester,
  ) async {
    final draft = BrewPoursDraft();
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [BrewPoursFields(draft: draft)]),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('pours-from-curve')), findsNothing);
    draft.fillFromCurve(
      BrewPours(
        bloomCount: 1,
        pourCount: 1,
        phases: const [
          BrewPourPhase(kind: BrewPourKind.bloom, number: 1, waterGrams: 50),
        ],
      ),
    );
    await settleWithWorkers(tester);
    expect(find.text('Filled in from the scale curve.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pours-from-curve-undo')));
    await settleWithWorkers(tester);
    expect(find.byKey(const ValueKey('pours-from-curve')), findsNothing);
    expect(draft.pourCount, isNull);
  });

  group('saved brews', () {
    late JournalRepository repository;
    late String filter;
    late Map<String, String> brews;

    setUp(() async {
      repository = JournalRepository(database);
      final coffee = (await repository.allCoffees()).single.id;
      filter = await repository.createMethod(name: 'V60', category: 'pourover');
      final espresso = await repository.createMethod(
        name: 'Espresso',
        category: 'espresso',
      );
      Future<String> brew(
        String method,
        String name, {
        BrewPours? pours,
      }) async {
        final id = await repository.createBrew(
          coffeeId: coffee,
          methodId: method,
          methodName: name,
          doseGrams: 15,
          bloomSeconds: 58,
          pours: pours,
        );
        await repository.saveScaleCurve(id, bloomAndPour());
        return id;
      }

      brews = {
        'blank': await brew(filter, 'V60'),
        'oneBloomGiven': await brew(
          filter,
          'V60',
          pours: BrewPours(bloomCount: 0),
        ),
        // Counts the curve disagrees with: left as they are.
        'recorded': await brew(
          filter,
          'V60',
          pours: BrewPours(bloomCount: 1, pourCount: 2),
        ),
        // Counts without details, as a repeated brew saves them.
        'pourCountOnly': await brew(
          filter,
          'V60',
          pours: BrewPours(pourCount: 2),
        ),
        'countsOnly': await brew(
          filter,
          'V60',
          pours: BrewPours(bloomCount: 1, pourCount: 1),
        ),
        'detailed': await brew(
          filter,
          'V60',
          pours: BrewPours(
            bloomCount: 1,
            pourCount: 1,
            phases: const [
              BrewPourPhase(
                kind: BrewPourKind.bloom,
                number: 1,
                waterGrams: 40,
              ),
            ],
          ),
        ),
        'espresso': await brew(espresso, 'Espresso'),
      };
    });

    test(
      'filter brews without details are offered, and saving is not an edit',
      () async {
        final found = await repository.poursFromCurves();
        expect(found.map((entry) => entry.brew.id).toSet(), {
          brews['blank'],
          brews['oneBloomGiven'],
          brews['countsOnly'],
          brews['pourCountOnly'],
        });
        final before = (await repository.brew(brews['blank']!))!.updatedAtMs;
        await repository.savePoursFromCurves(found);
        final blank = (await repository.brew(brews['blank']!))!;
        expect((blank.bloomCount, blank.pourCount), (1, 1));
        expect(blank.bloomSeconds, 31);
        expect(blank.updatedAtMs, before);
        final given = (await repository.brew(brews['oneBloomGiven']!))!;
        expect((given.bloomCount, given.pourCount), (0, 2));
        expect(given.bloomSeconds, isNull);
        final counts = (await repository.brew(brews['countsOnly']!))!;
        expect(counts.pourPhasesJson, contains('"waterGrams":50'));
        expect(counts.bloomSeconds, 31);
        final onlyPours = (await repository.brew(brews['pourCountOnly']!))!;
        expect((onlyPours.bloomCount, onlyPours.pourCount), (0, 2));
        expect(onlyPours.bloomSeconds, isNull);
        expect(onlyPours.pourPhasesJson, contains('"waterGrams":200'));
        final detailed = (await repository.brew(brews['detailed']!))!;
        expect(detailed.pourPhasesJson, contains('"waterGrams":40'));
        expect(detailed.bloomSeconds, 58);
        expect(await repository.poursFromCurves(), isEmpty);
      },
    );
  });

  testWidgets('a saved brew offers its blooms and pours, one by one or all '
      'at once from Settings', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = JournalRepository(database);
    late String first;
    await tester.runAsync(() async {
      final coffee = (await repository.allCoffees()).single.id;
      final method = await repository.createMethod(
        name: 'V60',
        category: 'pourover',
      );
      for (var i = 0; i < 2; i++) {
        final id = await repository.createBrew(
          coffeeId: coffee,
          methodId: method,
          methodName: 'V60',
          doseGrams: 15,
          bloomSeconds: 58,
          brewedAt: DateTime.now().subtract(Duration(hours: i + 1)),
        );
        await repository.saveScaleCurve(id, bloomAndPour());
        if (i == 0) first = id;
      }
    });
    Future<void> settle(Finder finder) => tester.runAsync(() async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await settleWithWorkers(tester);
    await tester.tap(find.text('Brews').last);
    await settleWithWorkers(tester);
    await tester.tap(find.byKey(ValueKey('brew-card-$first')));
    await settleWithWorkers(tester);
    final card = find.byKey(const ValueKey('brew-detail-pours-from-curve'));
    await settle(card);
    expect(find.text('The curve shows 1 bloom and 1 pour.'), findsOneWidget);
    await tester.ensureVisible(card);
    await tester.tap(find.byKey(const ValueKey('brew-detail-pours-save')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settleWithWorkers(tester);
    expect(card, findsNothing);
    final saved = (await tester.runAsync(() => repository.brew(first)))!;
    expect((saved.bloomCount, saved.pourCount), (1, 1));
    expect(saved.bloomSeconds, 31);
    expect(find.text('31 s'), findsOneWidget);
    expect(find.text('58 s'), findsNothing);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await settleWithWorkers(tester);

    await tester.tap(find.byTooltip('Settings'));
    await settleWithWorkers(tester);
    final tile = find.byKey(const ValueKey('pours-from-curves'));
    await tester.scrollUntilVisible(tile, 300);
    await tester.ensureVisible(tile);
    await settleWithWorkers(tester);
    await tester.tap(tile);
    final fill = find.byKey(const ValueKey('pours-from-curves-fill'));
    await settle(fill);
    expect(find.textContaining('of 1 brew will be filled'), findsOneWidget);
    await tester.tap(fill);
    await settle(find.text('1 brew filled'));
    expect(find.text('1 brew filled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
