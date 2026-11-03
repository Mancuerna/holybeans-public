import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_plan.dart';

/// Fills missing water amounts from [plan], retaining every recorded field.
BrewPours fillPlannedWater(BrewPours recorded, PourPlan plan) {
  if (plan.problem != null ||
      recorded.bloomCount != plan.blooms.length ||
      recorded.pourCount != plan.pours) {
    return recorded;
  }
  final phases = {
    for (final phase in recorded.phases) (phase.kind, phase.number): phase,
  };
  return BrewPours(
    bloomCount: recorded.bloomCount,
    pourCount: recorded.pourCount,
    phases: [
      for (final step in plan.steps)
        _fill(
          phases[(
            step.kind == PourStepKind.bloom
                ? BrewPourKind.bloom
                : BrewPourKind.pour,
            step.number,
          )],
          step,
        ),
    ],
  );
}

BrewPourPhase _fill(BrewPourPhase? recorded, PourStep step) {
  if (recorded?.waterGrams != null) return recorded!;
  return BrewPourPhase(
    kind: step.kind == PourStepKind.bloom
        ? BrewPourKind.bloom
        : BrewPourKind.pour,
    number: step.number,
    waterGrams: step.addGrams,
    waterFromPlan: true,
    durationSeconds: recorded?.durationSeconds,
    restSeconds: recorded?.restSeconds,
  );
}
