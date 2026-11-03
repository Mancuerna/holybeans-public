import 'package:flutter/material.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// The coffee and the recipe being written, as the figures the cards show
/// ("23 g → 37 g", "1:1.6", "0:18"), fixed above the form so what is brewed
/// stays in sight while any field below is edited. Empty until there is a
/// coffee, a dose or an output.
class BrewRecipeHeader extends StatelessWidget {
  const BrewRecipeHeader({super.key, required this.model});

  final BrewFormModel model;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    return ListenableBuilder(
      listenable: Listenable.merge([
        model,
        draft.dose,
        draft.water,
        draft.beverage,
        draft.durationMinutes,
        draft.durationSeconds,
      ]),
      builder: (context, _) {
        final dose = parseNumber(draft.dose.text);
        final output = parseNumber(
          model.isEspresso ? draft.beverage.text : draft.water.text,
        );
        final minutes = int.tryParse(draft.durationMinutes.text.trim());
        final seconds = int.tryParse(draft.durationSeconds.text.trim());
        final time = minutes == null && seconds == null
            ? null
            : (minutes ?? 0) * 60 + (seconds ?? 0);
        final method = model.selectedMethod;
        final ratio = formatBrewRatio(
          methodCategory: method?.category,
          methodName: model.methodName,
          doseGrams: dose,
          waterGrams: parseNumber(draft.water.text),
          beverageGrams: parseNumber(draft.beverage.text),
          localeName: regionalLocale.toString(),
        );
        final parts = [
          if (dose != null && output != null)
            '${formatGrams(dose, regionalLocale.toString())} → ${formatGrams(output, regionalLocale.toString())}'
          else if (dose != null)
            formatGrams(dose, regionalLocale.toString())
          else if (output != null)
            formatGrams(output, regionalLocale.toString()),
          ?ratio,
          if (time != null && time > 0) formatDuration(time),
        ];
        final coffee = model.coffees
            .where((row) => row.id == model.coffeeId)
            .firstOrNull
            ?.name;
        if (parts.isEmpty && coffee == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        // The sheet centres its children; the coffee and figures read from
        // the start like the form below them.
        return Padding(
          key: const ValueKey('brew-recipe-header'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (coffee != null)
                  Text(
                    coffee,
                    key: const ValueKey('brew-header-coffee'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (parts.isNotEmpty) BrewRecipeFigures(parts, large: true),
              ],
            ),
          ),
        );
      },
    );
  }
}
