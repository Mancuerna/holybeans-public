import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/pour_plan.dart';

void main() {
  test('two blooms and three equal pours share the water left', () {
    final plan = PourPlan(
      doseGrams: 15,
      ratio: 16,
      blooms: const [
        BloomStep(doseMultiple: 2, waitSeconds: 40),
        BloomStep(doseMultiple: 1, waitSeconds: 20),
      ],
    );
    expect(plan.problem, isNull);
    expect(plan.totalWaterGrams, 240);
    expect(plan.bloomWaterGrams, 45);
    expect(plan.bloomSeconds, 60);
    final steps = plan.steps;
    expect([for (final step in steps) step.startSecond], [0, 40, 60, 90, 120]);
    expect(
      [for (final step in steps) step.targetGrams],
      [30, 45, 110, 175, 240],
    );
    expect(steps[2].addGrams, 65);
    expect((steps[2].kind, steps[2].number), (PourStepKind.pour, 1));
    expect(plan.pouringEndSecond, 150);

    expect(plan.stepAt(-1), isNull);
    expect(plan.stepAt(45)!.number, 2);
    expect(plan.nextAfter(45)!.startSecond, 60);
    expect(plan.nextAfter(120), isNull);
  });

  test('the planned weight rises over each pour and holds in between', () {
    final plan = PourPlan(
      doseGrams: 20,
      ratio: 15,
      blooms: const [BloomStep(doseMultiple: 2, waitSeconds: 30)],
      pours: 2,
      pourIntervalSeconds: 40,
    );
    expect(plan.plannedGramsAt(0), 0);
    expect(plan.plannedGramsAt(5), 20);
    expect(plan.plannedGramsAt(20), 40);
    expect(plan.plannedGramsAt(35), closeTo(40 + 130 / 2, 1e-9));
    expect(plan.plannedGramsAt(200), 300);
  });

  test('plans that cannot work say why', () {
    expect(PourPlan(doseGrams: 0, ratio: 16).problem, PourPlanProblem.dose);
    expect(PourPlan(doseGrams: 15, ratio: 1).problem, PourPlanProblem.ratio);
    expect(
      PourPlan(
        doseGrams: 15,
        ratio: 16,
        blooms: const [PourPlan.standardBloom],
        pours: 0,
      ).problem,
      PourPlanProblem.pours,
    );
    // Explicit zero blooms is a valid recipe.
    final bare = PourPlan(doseGrams: 15, ratio: 16);
    expect(bare.problem, isNull);
    expect(bare.withAtLeastOneBloom().problem, isNull);
    expect(bare.withAtLeastOneBloom().blooms.single.doseMultiple, 2);
    expect(
      PourPlan(
        doseGrams: 15,
        ratio: 3,
        blooms: const [BloomStep(doseMultiple: 3, waitSeconds: 30)],
      ).problem,
      PourPlanProblem.bloomWater,
    );
  });

  test('a method remembers the recipe, not the dose', () {
    final plan = PourPlan.standard(18).copyWith(pours: 4);
    final copy = PourPlan.fromJson(plan.toJson(), doseGrams: 12);
    expect(copy.doseGrams, 12);
    expect(copy.ratio, 16);
    expect(copy.pours, 4);
    expect(copy.blooms.single.doseMultiple, 2);
    expect(copy.steps.first.addGrams, 24);
    expect(() => PourPlan.fromJson('[]', doseGrams: 12), throwsFormatException);
  });

  test('a brew starts from the saved recipe, else the ratio typed', () {
    final saved = PourPlan.standard(18).copyWith(pours: 4, ratio: 15).toJson();
    final remembered = PourPlan.toStart(
      saved: saved,
      doseGrams: 20,
      waterGrams: 340,
    );
    expect((remembered.doseGrams, remembered.ratio), (20, 17));
    expect(remembered.pours, 4);
    expect(PourPlan.toStart(doseGrams: 20, waterGrams: 340).ratio, 17);
    expect(PourPlan.toStart(doseGrams: 20).ratio, 16);
    // A recipe that no longer reads starts from the standard one.
    expect(PourPlan.toStart(saved: '[]', doseGrams: 20).ratio, 16);
  });
}
