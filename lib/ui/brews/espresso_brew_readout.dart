import 'package:flutter/material.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class EspressoBrewReadout extends StatelessWidget {
  const EspressoBrewReadout({
    super.key,
    required this.grams,
    required this.doseGrams,
    required this.targetGrams,
    required this.targetRatio,
    this.showRatio = true,
  });

  final double? grams;
  final double? doseGrams;
  final double? targetGrams;
  final double targetRatio;
  final bool showRatio;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    String weight(double? v) => v == null ? '—' : '${number.format(v)} g';
    final currentRatio = filterRecipeRatio(doseGrams, grams);
    String ratio(double? v) => v == null
        ? '—'
        : '1:${formatBrewRatioMultiplier(v, regionalLocale.toString())}';
    return Wrap(
      key: const ValueKey('espresso-brew-progress'),
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          '${s.curveWeight}: ${weight(grams)}',
          key: const ValueKey('espresso-current-weight'),
        ),
        if (showRatio) ...[
          Text(
            '${s.brewTargetBeverage}: ${weight(targetGrams)}',
            key: const ValueKey('espresso-target-weight'),
          ),
          Text('${s.filterCurrentRatio}: ${ratio(currentRatio)}'),
          Text('${s.filterTargetRatio}: ${ratio(targetRatio)}'),
        ],
      ],
    );
  }
}
