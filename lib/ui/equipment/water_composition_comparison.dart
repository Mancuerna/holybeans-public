import 'package:flutter/material.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_calculator_fields.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:intl/intl.dart';

class WaterCompositionComparison extends StatelessWidget {
  const WaterCompositionComparison({
    super.key,
    required this.recipe,
    this.showDerived = false,
  });
  final WaterRecipe recipe;
  final bool showDerived;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.##', regionalLocale.toString());
    final waters = [
      recipe.base,
      if (recipe.target != null) recipe.target!,
      recipe.result,
    ];
    final labels = [
      s.waterInitial,
      if (recipe.target != null) s.waterTarget,
      s.waterResult,
    ];
    TableRow row(String label, double? Function(WaterComposition) value) {
      final goal = recipe.target == null ? null : value(recipe.target!);
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(label),
          ),
          for (var i = 0; i < waters.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              child: Text(
                value(waters[i]) == null
                    ? '—'
                    : number.format(value(waters[i])),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: i == waters.length - 1 ? FontWeight.w600 : null,
                  color:
                      i == waters.length - 1 &&
                          goal != null &&
                          value(waters[i]) != null &&
                          (value(waters[i])! - goal).abs() > .1
                      ? Theme.of(context).colorScheme.tertiary
                      : null,
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.waterFinalComposition,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          s.waterCompositionUnits,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final label in labels)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 3,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            row('KH', (w) => w.kh),
            for (final ion in waterDisplayIons)
              row(ionSymbol(ion), (w) => w[ion]),
            if (showDerived) ...[
              row('GH', (w) => w.gh),
              row(s.waterMassRatio, (w) => w.calciumMagnesiumMassRatio),
            ],
          ],
        ),
      ],
    );
  }
}
