import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/pour_progress.dart';

void main() {
  final plan = PourPlan.standard(15);
  test(
    'bars follow water independently of time and preserve unknown readings',
    () {
      PourProgress at(int second, double? grams) =>
          PourProgress(plan: plan, second: second, grams: grams);
      expect(at(52, 76).filled(plan.steps[1]), 46);
      expect(at(52, 76).fillingIndex, 1);
      expect(at(52, 100).fillingIndex, 1);
      expect(at(25, 120).fillingIndex, 2);
      expect(at(100, 20).fillingIndex, 0);
      expect(at(100, null).fillingIndex, 2);
      expect(at(100, null).filled(plan.steps[1]), isNull);
      expect(at(100, double.nan).grams, isNull);
      expect(at(100, -10).filled(plan.steps.first), 0);
      expect(at(200, 300).filled(plan.steps.last), 70);
      expect(at(200, 300).fillingIndex, 3);
    },
  );
  test(
    'brew values override remembered recipe; empty fields keep defaults',
    () {
      final saved = plan.copyWith(pours: 4, ratio: 15).toJson();
      final brew = PourPlan.toStart(
        saved: saved,
        doseGrams: 20,
        waterGrams: 340,
        bloomSeconds: 50,
        brewPours: BrewPours(
          bloomCount: 2,
          pourCount: 5,
          phases: const [
            BrewPourPhase(
              kind: BrewPourKind.bloom,
              number: 1,
              waterGrams: 35,
              durationSeconds: 8,
              restSeconds: 22,
            ),
          ],
        ),
      );
      expect(brew.ratio, 17);
      expect(brew.pours, 5);
      expect(brew.blooms.first.doseMultiple, 1.75);
      expect(brew.blooms.first.waitSeconds, 30);
      expect(brew.blooms.last.waitSeconds, 25);
      expect(PourPlan.toStart(saved: saved, doseGrams: 20).pours, 4);
      expect(
        PourPlan.toStart(
          saved: saved,
          doseGrams: 20,
          brewPours: BrewPours(bloomCount: 0, pourCount: 10),
        ).problem,
        isNull,
      );
      expect(
        PourPlan.toStart(
          saved: saved,
          doseGrams: 20,
          brewPours: BrewPours(pourCount: 0),
        ).problem,
        PourPlanProblem.pours,
      );
    },
  );
}
