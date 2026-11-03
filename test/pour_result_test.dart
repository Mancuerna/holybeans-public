import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final blooms in [0, 2]) {
    test(
      'assistant without a curve returns $blooms blooms and pours, no measurements',
      () {
        final draft = BrewDraft();
        addTearDown(draft.dispose);
        draft.bloom.text = '90';
        draft.pours.setCount(BrewPourKind.bloom, 1);
        draft.pours.phaseDraft(BrewPourKind.bloom, 1).water.text = '35';
        final plan = PourPlan(
          doseGrams: 15,
          ratio: 16,
          pours: 4,
          blooms: List.filled(blooms, PourPlan.standardBloom),
        );
        draft.applyPour(plan, 180);
        expect((draft.pours.bloomCount, draft.pours.pourCount), (blooms, 4));
        expect(draft.pours.value.phases, isEmpty);
        expect(draft.pours.fromCurve, isFalse);
        expect(draft.pours.takesCurve, isTrue);
        expect(draft.bloom.text, blooms == 0 ? '' : '90');
        expect(draft.hasValidPourDetails, isTrue);
        final next = PourPlan.toStart(
          doseGrams: 15,
          brewPours: draft.pours.value,
          bloomSeconds: int.tryParse(draft.bloom.text),
        );
        expect((next.blooms.length, next.pours), (blooms, 4));
      },
    );
  }
  test(
    'assistant curve replaces planned fields and undo restores the recipe',
    () {
      final draft = BrewDraft();
      addTearDown(draft.dispose);
      draft.pours.setCount(BrewPourKind.bloom, 1);
      draft.pours.setCount(BrewPourKind.pour, 4);
      draft.pours.phaseDraft(BrewPourKind.bloom, 1).water.text = '30.00';
      draft.bloom.text = '45';
      final times = <int>[];
      final weight = <double>[];
      for (var second = 0; second <= 90; second++) {
        times.add(second * 1000);
        weight.add(
          second < 5
              ? 0
              : second < 15
              ? (second - 5) * 3
              : second < 45
              ? 30
              : second < 65
              ? 30 + (second - 45) * 5
              : 130,
        );
      }
      final curve = ShotCurve(timesMs: times, flow: const [], weight: weight);
      draft.applyPour(
        PourPlan.standard(15).copyWith(pours: 4),
        90,
        pouredGrams: 130,
        curve: curve,
      );
      expect(draft.water.text, '130');
      expect(draft.durationMinutes.text, '1');
      expect(draft.durationSeconds.text, '30');
      expect(draft.pours.pourCount, 1);
      expect(draft.pours.bloomCount, 1);
      expect(draft.pours.value.phases.last.waterGrams, 100);
      expect(draft.bloom.text, isNot('45'));
      draft.pours.undoFromCurve();
      expect(draft.pours.pourCount, 4);
      expect(draft.pours.value.phases.single.waterGrams, 30);
      expect(draft.pours.phaseDraft(BrewPourKind.bloom, 1).water.text, '30.00');
      expect(draft.bloom.text, '45');
    },
  );
}
