import 'dart:convert';
import 'dart:math' as math;

import 'package:holybeans/domain/brew_pours.dart';

/// A bloom: water to wet the bed, as a multiple of the dose, and how long
/// to wait before the next step.
class BloomStep {
  const BloomStep({required this.doseMultiple, required this.waitSeconds});

  final double doseMultiple;
  final int waitSeconds;
}

enum PourStepKind { bloom, pour }

/// One moment of a pour plan: when it starts, how much water to add and
/// the total the scale should reach.
class PourStep {
  const PourStep({
    required this.kind,
    required this.number,
    required this.startSecond,
    required this.addGrams,
    required this.targetGrams,
  });

  final PourStepKind kind;

  /// 1-based among the steps of its kind.
  final int number;
  final int startSecond;
  final double addGrams;
  final double targetGrams;
}

/// A guided filter recipe: [doseGrams] at 1:[ratio], some blooms, then
/// [pours] equal pours of the water that is left, [pourIntervalSeconds]
/// apart.
class PourPlan {
  PourPlan({
    required this.doseGrams,
    required this.ratio,
    this.blooms = const [],
    this.pours = 3,
    this.pourIntervalSeconds = 30,
  });

  /// The recipe without a dose: what a method remembers.
  factory PourPlan.fromJson(String source, {required double doseGrams}) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Pour plan is not an object');
    final blooms = json['blooms'];
    if (blooms is! List) throw const FormatException('Pour plan has no blooms');
    return PourPlan(
      doseGrams: doseGrams,
      ratio: (json['ratio'] as num).toDouble(),
      blooms: [
        for (final bloom in blooms.cast<Map<Object?, Object?>>())
          BloomStep(
            doseMultiple: (bloom['x'] as num).toDouble(),
            waitSeconds: (bloom['s'] as num).round(),
          ),
      ],
      pours: (json['pours'] as num).round(),
      pourIntervalSeconds: (json['interval'] as num).round(),
    );
  }

  /// A common starting point: one bloom of twice the dose for 45 s, then
  /// three pours 30 s apart at 1:16.
  factory PourPlan.standard(double doseGrams) =>
      PourPlan(doseGrams: doseGrams, ratio: 16, blooms: const [standardBloom]);

  /// What a brew starts from: the method's [saved] recipe at [doseGrams],
  /// or the standard one at the ratio [waterGrams] gives, when typed.
  factory PourPlan.toStart({
    String? saved,
    required double doseGrams,
    double? waterGrams,
    BrewPours? brewPours,
    int? bloomSeconds,
  }) {
    var plan = PourPlan.standard(doseGrams);
    if (saved != null) {
      try {
        final remembered = PourPlan.fromJson(saved, doseGrams: doseGrams);
        if (remembered.problem == null) plan = remembered;
      } on Object {
        // An unreadable recipe falls back to the standard one.
      }
    }
    final count = brewPours?.bloomCount ?? plan.blooms.length;
    final blooms = <BloomStep>[];
    for (var index = 0; index < count; index++) {
      final phase = brewPours?.phases
          .where((p) => p.kind == BrewPourKind.bloom && p.number == index + 1)
          .firstOrNull;
      final fallback = index < plan.blooms.length
          ? plan.blooms[index]
          : standardBloom;
      final measuredTime =
          (phase?.durationSeconds ?? 0) + (phase?.restSeconds ?? 0);
      blooms.add(
        BloomStep(
          doseMultiple: phase?.waterGrams != null && doseGrams > 0
              ? phase!.waterGrams! / doseGrams
              : fallback.doseMultiple,
          waitSeconds: measuredTime > 0
              ? measuredTime
              : bloomSeconds != null && bloomSeconds > 0
              ? math.max(1, (bloomSeconds / count).round())
              : fallback.waitSeconds,
        ),
      );
    }
    return plan.copyWith(
      ratio: waterGrams != null && doseGrams > 0
          ? waterGrams / doseGrams
          : plan.ratio,
      blooms: blooms,
      pours: brewPours?.pourCount ?? plan.pours,
    );
  }

  /// A recipe may explicitly omit blooms.
  static const minBlooms = 0;
  static const maxBlooms = 3;

  /// The bloom a plan gets when it has none: twice the dose for 45 s.
  static const standardBloom = BloomStep(doseMultiple: 2, waitSeconds: 45);
  static const maxPours = 10;

  final double doseGrams;
  final double ratio;
  final List<BloomStep> blooms;
  final int pours;
  final int pourIntervalSeconds;

  double get totalWaterGrams => doseGrams * ratio;
  double get bloomWaterGrams =>
      blooms.fold(0, (sum, bloom) => sum + bloom.doseMultiple * doseGrams);
  int get bloomSeconds =>
      blooms.fold(0, (sum, bloom) => sum + bloom.waitSeconds);

  /// Why the plan cannot be followed, or null when it can.
  PourPlanProblem? get problem {
    if (!doseGrams.isFinite || doseGrams <= 0) return PourPlanProblem.dose;
    if (!ratio.isFinite || ratio <= 1 || ratio > 30) {
      return PourPlanProblem.ratio;
    }
    if (blooms.length < minBlooms ||
        blooms.length > maxBlooms ||
        blooms.any(
          (bloom) =>
              !bloom.doseMultiple.isFinite ||
              bloom.doseMultiple <= 0 ||
              bloom.waitSeconds <= 0,
        )) {
      return PourPlanProblem.bloom;
    }
    if (pours < 1 || pours > maxPours || pourIntervalSeconds <= 0) {
      return PourPlanProblem.pours;
    }
    // The pours need some water left after the blooms.
    if (bloomWaterGrams >= totalWaterGrams - pours) {
      return PourPlanProblem.bloomWater;
    }
    return null;
  }

  /// The steps in order. Each pour adds an equal share of the water left
  /// after the blooms.
  List<PourStep> get steps {
    final steps = <PourStep>[];
    var second = 0;
    var total = 0.0;
    for (final (index, bloom) in blooms.indexed) {
      final grams = bloom.doseMultiple * doseGrams;
      total += grams;
      steps.add(
        PourStep(
          kind: PourStepKind.bloom,
          number: index + 1,
          startSecond: second,
          addGrams: grams,
          targetGrams: total,
        ),
      );
      second += bloom.waitSeconds;
    }
    final share = (totalWaterGrams - total) / pours;
    for (var pour = 1; pour <= pours; pour++) {
      // The last pour lands exactly on the total, whatever the rounding.
      final target = pour == pours ? totalWaterGrams : total + share;
      steps.add(
        PourStep(
          kind: PourStepKind.pour,
          number: pour,
          startSecond: second,
          addGrams: target - total,
          targetGrams: target,
        ),
      );
      total = target;
      second += pourIntervalSeconds;
    }
    return steps;
  }

  /// When the last pour should be finished, before the drawdown.
  int get pouringEndSecond => bloomSeconds + pours * pourIntervalSeconds;

  /// The step under way at [second], or null before the start.
  PourStep? stepAt(int second) {
    PourStep? current;
    for (final step in steps) {
      if (step.startSecond > second) break;
      current = step;
    }
    return current;
  }

  /// The next step after [second], or null once all have started.
  PourStep? nextAfter(int second) {
    for (final step in steps) {
      if (step.startSecond > second) return step;
    }
    return null;
  }

  /// Water the scale should show at [second] when each step is poured
  /// steadily over [pourSeconds], or until the next step if sooner.
  double plannedGramsAt(double second, {double pourSeconds = 10}) =>
      plannedPourGramsAt(steps, second, pourSeconds: pourSeconds);

  /// The recipe without the dose, for a method to remember.
  String toJson() => jsonEncode({
    'ratio': ratio,
    'blooms': [
      for (final bloom in blooms)
        {'x': bloom.doseMultiple, 's': bloom.waitSeconds},
    ],
    'pours': pours,
    'interval': pourIntervalSeconds,
  });

  /// This plan, with the standard bloom if it has none.
  PourPlan withAtLeastOneBloom() =>
      blooms.isEmpty ? copyWith(blooms: const [standardBloom]) : this;

  PourPlan copyWith({
    double? doseGrams,
    double? ratio,
    List<BloomStep>? blooms,
    int? pours,
    int? pourIntervalSeconds,
  }) => PourPlan(
    doseGrams: doseGrams ?? this.doseGrams,
    ratio: ratio ?? this.ratio,
    blooms: blooms ?? this.blooms,
    pours: pours ?? this.pours,
    pourIntervalSeconds: pourIntervalSeconds ?? this.pourIntervalSeconds,
  );
}

enum PourPlanProblem { dose, ratio, bloom, pours, bloomWater }

/// Water expected at [second] using already prepared pour [steps].
///
/// Each step rises steadily over [pourSeconds], or until the next step if sooner.
double plannedPourGramsAt(
  List<PourStep> steps,
  double second, {
  double pourSeconds = 10,
}) {
  var grams = 0.0;
  for (final (index, step) in steps.indexed) {
    if (second < step.startSecond) break;
    final untilNext = index + 1 < steps.length
        ? steps[index + 1].startSecond - step.startSecond
        : pourSeconds;
    final span = math.max(1.0, math.min(pourSeconds, untilNext.toDouble()));
    final done = ((second - step.startSecond) / span).clamp(0.0, 1.0);
    grams = step.targetGrams - step.addGrams * (1 - done);
  }
  return grams;
}
