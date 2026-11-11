import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late JournalRepository repository;
  late String coffeeId;
  late String methodId;

  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    coffeeId = await repository.createCoffee(name: 'Kenya', roaster: 'R');
    methodId = await repository.createMethod(name: 'V60', category: 'pourover');
  });
  tearDown(() => database.close());

  test('aggregate bloom time is validated even when its fields are folded', () {
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    for (final text in ['', '45']) {
      draft.bloom.text = text;
      expect(draft.hasValidPourDetails, isTrue);
    }
    for (final text in ['wrong', '-1', '0', '4.5']) {
      draft.bloom.text = text;
      expect(draft.hasValidPourDetails, isFalse);
    }
    draft.pours.setCount(BrewPourKind.bloom, 0);
    expect(draft.hasValidPourDetails, isTrue);
  });

  Future<Brew> brew({
    double? dose,
    double? water,
    double? beverage,
    int? time,
    String? notes,
  }) async {
    final id = await repository.createBrew(
      coffeeId: coffeeId,
      methodId: methodId,
      methodName: 'V60',
      grindSetting: '22',
      doseGrams: dose,
      waterGrams: water,
      beverageGrams: beverage,
      temperatureC: 94,
      timeSeconds: time,
      notes: notes,
      profileName: 'Bloom heavy',
    );
    return (await repository.brew(id))!;
  }

  test('a draft starts from the edited brew or the repeated recipe', () async {
    final saved = await brew(
      dose: 15,
      water: 250,
      beverage: 220,
      time: 185,
      notes: 'Juicy',
    );

    final edit = BrewDraft(existing: saved);
    expect(edit.dose.text, '15');
    expect(edit.beverage.text, '220');
    expect((edit.durationMinutes.text, edit.durationSeconds.text), ('3', '05'));
    expect(edit.timeSeconds, 185);
    expect(edit.notes.text, 'Juicy');
    edit.dispose();

    // Repeating keeps the recipe and the user's notes, but not measurements.
    final again = BrewDraft(seed: saved, repeat: true);
    expect(again.dose.text, '15');
    expect(again.water.text, '250');
    expect(again.profile.text, 'Bloom heavy');
    expect(again.beverage.text, isEmpty);
    expect(again.timeSeconds, isNull);
    expect(again.notes.text, 'Juicy');
    again.dispose();

    final thawed = BrewDraft(initialDoseGrams: 17.5);
    expect(thawed.dose.text, '17.5');
    thawed.dispose();
  });

  test('method memory fills the recipe and spares typed fields', () async {
    final last = await brew(dose: 15, water: 250, beverage: 220);
    final draft = BrewDraft()..water.text = '300';

    draft.applyMemory(last, espresso: false);
    expect(draft.dose.text, '15');
    expect(draft.water.text, '300', reason: 'typed by the user');
    expect(draft.beverage.text, isEmpty, reason: 'a result, not recipe');
    expect(draft.grindSetting.text, '22');
    expect(draft.temperature.text, '94');
    expect(draft.profile.text, 'Bloom heavy');

    // A second memory replaces what the first one wrote, not edits.
    final other = await brew(dose: 18, water: 36);
    draft.dose.text = '15';
    draft.temperature.text = '90';
    draft.applyMemory(other, espresso: true);
    expect(draft.dose.text, '18');
    expect(draft.beverage.text, isEmpty, reason: 'espresso target is beverage');
    expect(draft.temperature.text, '90');
    draft.dispose();
  });

  test(
    'memory recalls counts, follows recipe changes and preserves manual edits',
    () async {
      final source = (await brew(
        dose: 15,
        water: 250,
      )).copyWith(bloomCount: const Value(2), pourCount: const Value(4));
      final draft = BrewDraft();
      addTearDown(draft.dispose);
      draft.applyMemory(source, espresso: false);
      expect((draft.pours.bloomCount, draft.pours.pourCount), (2, 4));
      expect(draft.pours.value.phases, isEmpty);
      expect(draft.pours.takesCurve, isTrue);
      draft.applyMemory(
        source.copyWith(bloomCount: const Value(0), pourCount: const Value(2)),
        espresso: false,
      );
      expect((draft.pours.bloomCount, draft.pours.pourCount), (0, 2));
      draft.pours.setCount(BrewPourKind.pour, null);
      draft.applyMemory(source, espresso: false);
      expect((draft.pours.bloomCount, draft.pours.pourCount), (2, null));
      draft.applyMemory(source, espresso: true);
      expect((draft.pours.bloomCount, draft.pours.pourCount), (null, null));
    },
  );

  test('memory never replaces entered phase details', () async {
    final source = (await brew()).copyWith(
      bloomCount: const Value(1),
      pourCount: const Value(4),
    );
    final draft = BrewDraft();
    addTearDown(draft.dispose);
    draft.applyMemory(source, espresso: false);
    draft.pours.phaseDraft(BrewPourKind.pour, 1).water.text = '50';
    draft.applyMemory(
      source.copyWith(pourCount: const Value(2)),
      espresso: false,
    );
    expect(draft.pours.pourCount, 4);
    expect(draft.pours.value.phases.single.waterGrams, 50);
  });

  test('a machine shot fills time, yield, temperature and profile', () {
    final draft = BrewDraft()..dose.text = '18';
    draft.applyShot(
      MeticulousShot(
        id: 'a',
        brewedAt: DateTime(2026, 9, 29, 8, 45),
        profileName: 'Linea Mini at Home',
        temperatureC: 90,
        timeSeconds: 30,
        yieldGrams: 42.4,
        peakPressureBar: 7.2,
        preinfusionSeconds: 8,
        firstDripSeconds: 10,
      ),
    );
    expect(draft.timeSeconds, 30);
    expect(draft.beverage.text, '42.4');
    expect(draft.temperature.text, '90');
    expect(draft.pressure.text, '7.2');
    expect(draft.preinfusion.text, '8');
    expect(draft.firstDrip.text, '10');
    expect(draft.profile.text, 'Linea Mini at Home');
    expect(draft.dose.text, '18');
    draft.applyShot(
      MeticulousShot(
        id: 'unknown',
        brewedAt: DateTime(2026, 10, 4),
        profileName: 'No weight',
      ),
    );
    expect(draft.firstDrip.text, isEmpty);
    draft.dispose();
  });

  test('the weight with the jug works out the beverage', () {
    final draft = BrewDraft()..jugTotal.text = '590,5';
    draft.applyTare(312);
    expect(draft.beverage.text, '278.5');
    // Without a jug, or with a total below its weight, nothing changes.
    draft.applyTare(null);
    draft.jugTotal.text = '200';
    draft.applyTare(312);
    expect(draft.beverage.text, '278.5');

    // An edited brew shows the full weight again.
    final edit = BrewDraft()..beverage.text = '250';
    edit.fillJugTotal(300);
    expect(edit.jugTotal.text, '550');
    draft.dispose();
    edit.dispose();
  });
}
