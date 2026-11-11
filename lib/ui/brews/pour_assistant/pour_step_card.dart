import 'package:flutter/material.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class PourStepCard extends StatelessWidget {
  const PourStepCard({
    super.key,
    required this.plan,
    required this.current,
    required this.pouringDone,
    required this.onScale,
    required this.atYourPace,
  });
  final PourPlan plan;
  final PourStep? current;
  final bool pouringDone;
  final double? onScale;
  final bool atYourPace;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grams = NumberFormat('0', regionalLocale.toString());
    final current = this.current;
    final onScale = this.onScale;
    final pours = plan.pours;
    final target = pouringDone ? plan.totalWaterGrams : current?.targetGrams;
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const ValueKey('pour-current-step'),
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: pouringDone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !atYourPace &&
                              onScale != null &&
                              onScale < plan.totalWaterGrams - 1
                          ? s.pourTimeComplete
                          : s.drawdown,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (onScale != null)
                      _ScaleProgress(
                        grams: onScale,
                        target: plan.totalWaterGrams,
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (current != null) ...[
                      Text(
                        current.kind == PourStepKind.bloom
                            ? s.bloomNumber(current.number)
                            : s.pourStepPour(current.number, pours),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        s.pourTo(grams.format(current.targetGrams)),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(s.pourAdd(grams.format(current.addGrams))),
                    ],
                    if ((onScale, target) case (final weight?, final goal?))
                      _ScaleProgress(grams: weight, target: goal),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The weight on the scale against the step's target: how much is left,
/// or how much over it went.
class _ScaleProgress extends StatelessWidget {
  const _ScaleProgress({required this.grams, required this.target});

  final double grams;
  final double target;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat('0', regionalLocale.toString());
    final left = target - grams;
    // A gram either way is as close as anyone pours.
    final over = left < -1;
    return Padding(
      key: const ValueKey('pour-scale-progress'),
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        [
          s.scaleOnScale(number.format(grams)),
          if (over)
            s.pourOver(number.format(-left))
          else if (left > 1)
            s.pourRemaining(number.format(left))
          else
            s.pourWait,
        ].join(', '),
        style: theme.textTheme.titleMedium?.copyWith(
          color: over ? theme.colorScheme.error : null,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
