import 'package:flutter/material.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_chart.dart';
import 'package:holybeans/ui/equipment/water_composition_comparison.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:intl/intl.dart';

class WaterCalculatorResult extends StatelessWidget {
  const WaterCalculatorResult({
    super.key,
    required this.recipe,
    this.showDerived = false,
  });
  final WaterRecipe recipe;
  final bool showDerived;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final result = recipe.result;
    final target = recipe.target;
    final number = NumberFormat('0.##', regionalLocale.toString());
    final grams = NumberFormat('0.000', regionalLocale.toString());
    final addedPotassium =
        recipe.base[WaterIon.potassium] == null &&
            result[WaterIon.potassium] == null
        ? recipe.added[WaterIon.potassium]!
        : 0.0;
    final excess =
        target != null &&
        (recipe.base.gh! > target.gh! + .01 ||
            recipe.base.kh! > target.kh! + .01);
    final changedIons =
        target != null &&
        WaterIon.values.any(
          (ion) =>
              target[ion] != null &&
              (result[ion] == null || (result[ion]! - target[ion]!).abs() > .1),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.waterDirectDose, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(s.waterDirectHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final salt in WaterSalt.values.where(
          (salt) => recipe.grams[salt]! > 1e-8,
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(saltLabel(s, salt)),
            subtitle: Text(_formula(salt, recipe.calcium)),
            trailing: Text(
              '${grams.format(recipe.grams[salt])} g',
              key: ValueKey('water-dose-${salt.name}'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        if (recipe.grams.values.every((g) => g < 1e-8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(s.waterNoDose),
          ),
        const Divider(),
        WaterCompositionComparison(recipe: recipe, showDerived: showDerived),
        if (addedPotassium > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${s.waterPotassiumAdded(number.format(addedPotassium))}. '
              '${s.waterPotassiumTotalUnknown}',
              key: const ValueKey('water-potassium-added'),
            ),
          ),
        if (excess)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(s.waterExcessHint, key: const ValueKey('water-excess')),
          ),
        if (recipe.calciumGhFraction != null &&
            target != null &&
            [WaterIon.calcium, WaterIon.magnesium].any(
              (ion) =>
                  result[ion] == null ||
                  (result[ion]! - target[ion]!).abs() > .01,
            ))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.waterMixtureApproximation,
              key: const ValueKey('water-mixture-approximation'),
            ),
          ),
        if (target != null &&
            ((result.gh == null || (result.gh! - target.gh!).abs() > .1) ||
                (result.kh == null || (result.kh! - target.kh!).abs() > .1)))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.waterUnreachableTarget,
              key: const ValueKey('water-unreachable-target'),
            ),
          ),
        if (changedIons)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.waterApproximationHint),
          ),
        const SizedBox(height: 16),
        WaterChart(
          points: [
            WaterChartPoint(
              id: 'initial',
              label: s.waterInitial,
              water: recipe.base,
              kind: WaterPointKind.initial,
            ),
            if (target != null)
              WaterChartPoint(
                id: 'target',
                label: s.waterTarget,
                water: target,
                kind: WaterPointKind.target,
              ),
            WaterChartPoint(
              id: 'result',
              label: s.waterResult,
              water: result,
              kind: WaterPointKind.result,
            ),
          ],
        ),
      ],
    );
  }
}

String _formula(WaterSalt salt, CalciumForm calcium) => switch (salt) {
  WaterSalt.epsom => 'MgSO₄·7H₂O',
  WaterSalt.magnesiumChloride => 'MgCl₂·6H₂O',
  WaterSalt.calciumChloride =>
    calcium == CalciumForm.anhydrous ? 'CaCl₂' : 'CaCl₂·2H₂O',
  WaterSalt.sodiumBicarbonate => 'NaHCO₃',
  WaterSalt.potassiumBicarbonate => 'KHCO₃',
};
