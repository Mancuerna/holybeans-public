import 'package:flutter/material.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:intl/intl.dart';

class WaterAlternativesPicker extends StatelessWidget {
  const WaterAlternativesPicker({super.key, required this.model});
  final WaterCalculatorModel model;

  @override
  Widget build(BuildContext context) {
    if (model.alternatives.length < 2) return const SizedBox.shrink();
    final s = AppLocalizations.of(context);
    final grams = NumberFormat('0.000', regionalLocale.toString());
    return ExpansionTile(
      key: const ValueKey('water-alternatives'),
      tilePadding: EdgeInsets.zero,
      title: Text(s.waterAlternatives),
      subtitle: Text(s.waterAlternativesHint),
      children: [
        Text(s.waterAutomaticHint),
        for (var i = 0; i < model.alternatives.length; i++)
          ListTile(
            key: ValueKey('water-alternative-$i'),
            contentPadding: EdgeInsets.zero,
            selected: i == model.selectedAlternative,
            leading: Icon(
              i == model.selectedAlternative
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(i == 0 ? s.waterAutomaticProposal : s.waterAlternative),
            subtitle: Text(
              [
                for (final salt in WaterSalt.values)
                  if (model.alternatives[i].grams[salt]! > 1e-8)
                    '${saltLabel(s, salt)}: ${grams.format(model.alternatives[i].grams[salt])} g',
              ].join('\n'),
            ),
            onTap: () => model.selectAlternative(i),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
