import 'package:holybeans/domain/pour_plan.dart';

/// Progress through cumulative recipe targets, not detected physical pours.
class PourProgress {
  PourProgress({required this.plan, required this.second, double? grams})
    : grams = grams != null && grams.isFinite ? grams : null;

  final PourPlan plan;
  final int second;
  final double? grams;

  int get scheduledIndex {
    final index = plan.steps.lastIndexWhere(
      (step) => step.startSecond <= second,
    );
    return index < 0 ? 0 : index;
  }

  int get fillingIndex {
    final steps = plan.steps;
    final weight = grams;
    if (weight == null) return scheduledIndex;
    if ((weight - steps[scheduledIndex].targetGrams).abs() < .001) {
      return scheduledIndex;
    }
    final index = steps.indexWhere((step) => step.targetGrams > weight);
    return index < 0 ? steps.length - 1 : index;
  }

  double? filled(PourStep step) => grams == null
      ? null
      : (grams! - (step.targetGrams - step.addGrams)).clamp(0, step.addGrams);
}
