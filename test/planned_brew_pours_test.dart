import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/planned_brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plan = PourPlan(
    doseGrams: 18,
    ratio: 16.5,
    blooms: const [
      BloomStep(doseMultiple: 3, waitSeconds: 45),
      BloomStep(doseMultiple: 3, waitSeconds: 45),
    ],
  );
  test(
    'breakdown supplies only water, marked as planned, with no invented timing',
    () {
      final pours = fillPlannedWater(
        BrewPours(bloomCount: 2, pourCount: 3),
        plan,
      );
      expect(pours.phases.map((p) => p.waterGrams), [54, 54, 63, 63, 63]);
      expect(pours.phases.every((p) => p.waterFromPlan), isTrue);
      expect(
        pours.phases.every(
          (p) =>
              p.durationSeconds == null &&
              p.restSeconds == null &&
              p.flowGramsPerSecond == null,
        ),
        isTrue,
      );
      expect(
        BrewPours.fromStorage(
          bloomCount: 2,
          pourCount: 3,
          phasesJson: pours.phasesJson,
        ).phasesJson,
        pours.phasesJson,
      );
    },
  );
  test('manual water and timings survive while blank water is completed', () {
    final pours = fillPlannedWater(
      BrewPours(
        bloomCount: 2,
        pourCount: 3,
        phases: const [
          BrewPourPhase(
            kind: BrewPourKind.bloom,
            number: 1,
            waterGrams: 50,
            durationSeconds: 10,
            restSeconds: 30,
          ),
          BrewPourPhase(
            kind: BrewPourKind.pour,
            number: 1,
            durationSeconds: 12,
          ),
        ],
      ),
      plan,
    );
    expect(pours.phases.first.waterGrams, 50);
    expect(pours.phases.first.waterFromPlan, isFalse);
    expect(pours.phases.first.flowGramsPerSecond, 5);
    final partial = pours.phases[2];
    expect(
      (partial.waterGrams, partial.durationSeconds, partial.waterFromPlan),
      (63, 12, true),
    );
    expect(
      partial.flowGramsPerSecond,
      isNull,
      reason: 'planned water is not measured flow',
    );
  });
  test(
    'invalid plans and mismatched counts leave recorded details unchanged',
    () {
      final recorded = BrewPours(bloomCount: 1, pourCount: 3);
      expect(fillPlannedWater(recorded, plan), same(recorded));
      expect(
        fillPlannedWater(recorded, PourPlan(doseGrams: 0, ratio: 16)),
        same(recorded),
      );
    },
  );
  test('an unused, invalid, or measured water plan never supplies details', () {
    final draft = BrewPoursDraft()
      ..bloomCount = 1
      ..pourCount = 3;
    addTearDown(draft.dispose);
    BrewPours save({bool curve = false, double? water = 300}) =>
        draft.valueForSave(dose: 18, water: water, hasCurve: curve);
    expect(save().phases, isEmpty);
    draft.expandWaterPlan(true);
    expect(save(curve: true).phases, isEmpty);
    expect(save(water: 10).phases, isEmpty);
    expect(save(water: null).phases, isEmpty);
    expect(save().phases.map((p) => p.waterGrams), [36, 88, 88, 88]);
    expect(
      draft.value.phases,
      isEmpty,
      reason: 'saving does not mutate a draft if the save later fails',
    );
    draft.setWaterPlanBloomRatio(5);
    expect(save().phases.map((p) => p.waterGrams), [90, 70, 70, 70]);
  });
  test(
    'editing planned water makes it manual; curve undo preserves its source',
    () {
      final draft = BrewPoursDraft()
        ..bloomCount = 1
        ..pourCount = 1;
      addTearDown(draft.dispose);
      final phase = draft.phaseDraft(BrewPourKind.bloom, 1)
        ..fill(
          const BrewPourPhase(
            kind: BrewPourKind.bloom,
            number: 1,
            waterGrams: 36,
            waterFromPlan: true,
          ),
        );
      final bloom = TextEditingController();
      addTearDown(bloom.dispose);
      draft.fillFromCurve(
        BrewPours(
          bloomCount: 1,
          pourCount: 1,
          phases: const [
            BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              waterGrams: 40,
              durationSeconds: 10,
            ),
          ],
        ),
        bloomTotal: bloom,
      );
      expect(draft.value.phases.first.waterFromPlan, isFalse);
      draft.undoFromCurve();
      expect(draft.value.phases.first.waterFromPlan, isTrue);
      phase.water.selection = const TextSelection.collapsed(offset: 1);
      expect(draft.value.phases.first.waterFromPlan, isTrue);
      phase.water.text = '38';
      expect(draft.value.phases.first.waterFromPlan, isFalse);
    },
  );
  test(
    'old phases remain unmarked and invalid planned metadata is rejected',
    () {
      expect(
        BrewPourPhase.fromJson({'kind': 'pour', 'number': 1, 'waterGrams': 80})
            .waterFromPlan,
        isFalse,
      );
      expect(
        () => BrewPourPhase.fromJson({
          'kind': 'pour',
          'number': 1,
          'waterGrams': 80,
          'waterFromPlan': 'yes',
        }),
        throwsFormatException,
      );
      expect(
        () => BrewPours(
          pourCount: 1,
          phases: const [
            BrewPourPhase(
              kind: BrewPourKind.pour,
              number: 1,
              waterFromPlan: true,
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );
}
