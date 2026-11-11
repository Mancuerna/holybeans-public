import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations_es.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown counts differ from zero and allow three blooms and ten pours',
    () {
      final unknown = BrewPours();
      expect(unknown.bloomCount, isNull);
      expect(unknown.phasesJson, isNull);
      expect(BrewPours(bloomCount: 0, pourCount: 0).bloomCount, 0);
      expect(BrewPours(bloomCount: 2, pourCount: 10).pourCount, 10);
      for (final count in [-1, 4]) {
        expect(() => BrewPours(bloomCount: count), throwsFormatException);
      }
      for (final count in [-1, 11]) {
        expect(() => BrewPours(pourCount: count), throwsFormatException);
      }
    },
  );

  test(
    'phases reject impossible measurements and mismatched or duplicate indices',
    () {
      BrewPours withPhase(BrewPourPhase phase) =>
          BrewPours(bloomCount: 1, pourCount: 1, phases: [phase]);
      for (final grams in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => withPhase(
            BrewPourPhase(
              kind: BrewPourKind.pour,
              number: 1,
              waterGrams: grams,
            ),
          ),
          throwsFormatException,
        );
      }
      for (final seconds in [-1, 0]) {
        expect(
          () => withPhase(
            BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              restSeconds: seconds,
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => withPhase(
            BrewPourPhase(
              kind: BrewPourKind.pour,
              number: 1,
              durationSeconds: seconds,
            ),
          ),
          throwsFormatException,
        );
      }
      const phase = BrewPourPhase(
        kind: BrewPourKind.pour,
        number: 1,
        waterGrams: 100,
        durationSeconds: 12,
      );
      expect(
        () => BrewPours(pourCount: 1, phases: [phase, phase]),
        throwsFormatException,
      );
      expect(() => BrewPours(phases: [phase]), throwsFormatException);
      expect(
        () =>
            withPhase(const BrewPourPhase(kind: BrewPourKind.bloom, number: 2)),
        throwsFormatException,
      );
      expect(
        () => withPhase(
          const BrewPourPhase(
            kind: BrewPourKind.pour,
            number: 1,
            restSeconds: 10,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => BrewPours.fromStorage(
          pourCount: 1,
          phasesJson: '[{"kind":"pour","number":1,"durationSeconds":2.5}]',
        ),
        throwsFormatException,
      );
    },
  );

  test('draft excludes removed phases and validates folded details', () {
    final draft = BrewPoursDraft();
    addTearDown(draft.dispose);
    draft.setCount(BrewPourKind.pour, 2);
    final phase = draft.phaseDraft(BrewPourKind.pour, 2);
    phase.water.text = '100,5';
    phase.duration.text = '12';
    expect(draft.value.phases.single.waterGrams, 100.5);
    phase.duration.text = '1.5';
    expect(draft.isValid, isFalse);
    draft.setCount(BrewPourKind.pour, 1);
    expect(draft.isValid, isTrue);
    expect(draft.value.phases, isEmpty);
  });

  group('repository and backups', () {
    late AppDatabase db;
    late JournalRepository repo;
    late String coffee;
    setUpAll(() => initializeDateFormatting('es'));
    setUp(() async {
      db = memoryDatabase();
      repo = JournalRepository(db);
      coffee = await repo.createCoffee(
        name: 'Filter test',
        roaster: 'Test',
        initialGrams: 250,
      );
    });
    tearDown(() => db.close());

    test(
      'save, edit, archive and v20 round trip preserve phase measurements',
      () async {
        final pours = BrewPours(
          bloomCount: 2,
          pourCount: 10,
          phases: const [
            BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              waterGrams: 36,
              durationSeconds: 8,
              restSeconds: 30,
            ),
            BrewPourPhase(
              kind: BrewPourKind.pour,
              number: 10,
              waterGrams: 50,
              durationSeconds: 9,
            ),
          ],
        );
        final id = await repo.createBrew(
          coffeeId: coffee,
          lotId: (await repo.coffeeLots(coffee)).single.id,
          methodName: 'V60',
          doseGrams: 18,
          bloomSeconds: 45,
          pours: pours,
        );
        var brew = await db.select(db.brews).getSingle();
        expect(brew.bloomSeconds, 45);
        expect(brew.bloomCount, 2);
        expect(brew.pourCount, 10);
        expect(
          BrewPours.fromStorage(
            bloomCount: 2,
            pourCount: 10,
            phasesJson: brew.pourPhasesJson,
          ).phases.last.durationSeconds,
          9,
        );
        // Callers unrelated to these fields must not erase existing recordings.
        await repo.saveBrew(
          id: id,
          coffeeId: coffee,
          lotId: (await repo.coffeeLots(coffee)).single.id,
          methodName: 'V60',
          doseGrams: 18,
          bloomSeconds: 45,
        );
        brew = await db.select(db.brews).getSingle();
        expect(brew.pourPhasesJson, pours.phasesJson);
        final edit = BrewPoursDraft(existing: brew);
        final repeat = BrewPoursDraft(repeated: brew);
        addTearDown(edit.dispose);
        addTearDown(repeat.dispose);
        expect(edit.value.phasesJson, pours.phasesJson);
        expect(repeat.value.bloomCount, 2);
        expect(repeat.value.pourCount, 10);
        expect(repeat.value.phases, isEmpty);
        final source = await JournalBackup(db).exportJson();
        expect(jsonDecode(source)['version'], JournalBackup.version);
        await JournalBackup(db).restoreJson(source);
        expect(
          (await db.select(db.brews).getSingle()).pourPhasesJson,
          pours.phasesJson,
        );
        final data = jsonDecode(source) as Map<String, dynamic>;
        data['data']['brews'][0]['pourCount'] = 1;
        await expectLater(
          JournalBackup(db).restoreJson(jsonEncode(data)),
          throwsFormatException,
        );
        expect((await db.select(db.brews).getSingle()).pourCount, 10);
        data['data']['brews'][0]['pourCount'] = 1.5;
        await expectLater(
          JournalBackup(db).restoreJson(jsonEncode(data)),
          throwsFormatException,
        );
        await repo.saveBrew(
          id: id,
          coffeeId: coffee,
          lotId: (await repo.coffeeLots(coffee)).single.id,
          methodName: 'V60',
          doseGrams: 18,
          pours: BrewPours(bloomCount: 0),
        );
        brew = await db.select(db.brews).getSingle();
        expect(brew.bloomCount, 0);
        expect(brew.pourPhasesJson, isNull);
        expect((await repo.coffeeLots(coffee)).single.remainingGrams, 232);
      },
    );

    test('v19 keeps legacy bloom time without inventing counts', () async {
      await repo.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        bloomSeconds: 45,
      );
      final source = jsonDecode(
        await JournalBackup(db).exportJson(),
      ) as Map<String, dynamic>;
      source['version'] = 19;
      final data = source['data'] as Map<String, dynamic>;
      for (final row in data['brews'] as List<dynamic>) {
        for (final key in ['bloomCount', 'pourCount', 'pourPhasesJson']) {
          row.remove(key);
        }
      }
      await JournalBackup(db).restoreJson(jsonEncode(source));
      final brew = await db.select(db.brews).getSingle();
      expect(brew.bloomSeconds, 45);
      expect(brew.bloomCount, isNull);
      expect(brew.pourCount, isNull);
      expect(brew.pourPhasesJson, isNull);
    });

    test(
      'sharing omits new fields by default and preserves explicit zero',
      () async {
        await repo.createBrew(
          coffeeId: coffee,
          methodName: 'V60',
          pours: BrewPours(
            bloomCount: 0,
            pourCount: 3,
            phases: const [
              BrewPourPhase(
                kind: BrewPourKind.pour,
                number: 1,
                waterGrams: 100.5,
                durationSeconds: 10,
              ),
            ],
          ),
        );
        final bean = await db.select(db.coffees).getSingle();
        final brew = await db.select(db.brews).getSingle();
        String share(Set<BrewParameter> fields) => BrewShareText.build(
          strings: AppLocalizationsEs(),
          coffee: bean,
          components: [],
          brew: brew,
          fields: fields,
        );
        expect(share(defaultSharedParameters), isNot(contains('Blooms:')));
        expect(share(defaultSharedParameters), isNot(contains('Vertidos:')));
        final text = share({
          BrewParameter.bloomCount,
          BrewParameter.pourCount,
          BrewParameter.pourDetails,
        });
        expect(text, contains('Blooms: 0'));
        expect(text, contains('Vertidos: 3'));
        expect(
          text,
          contains('Vertido 1 · 100.5 g · Vertido: 10 s · 10.1 g/s'),
        );
      },
    );
  });

  test('the flow of a phase comes from its water and pouring time', () {
    BrewPourPhase phase({double? water, int? seconds}) => BrewPourPhase(
      kind: BrewPourKind.pour,
      number: 1,
      waterGrams: water,
      durationSeconds: seconds,
    );
    expect(
      phase(water: 50, seconds: 6).flowGramsPerSecond,
      closeTo(8.33, 0.01),
    );
    expect(phase(water: 50).flowGramsPerSecond, isNull);
    expect(phase(seconds: 6).flowGramsPerSecond, isNull);
  });
}
