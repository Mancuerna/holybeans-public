import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/detail_widgets.dart' show formatGrams;
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class BrewDoseSourceField extends StatelessWidget {
  const BrewDoseSourceField({super.key, required this.model});
  final BrewFormModel model;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final brew = model.existing!;
    final sameLot = brew.lotId == model.lotId;
    final portions = model.dosePortions;
    final original = portions
        .where((p) => p.id == brew.frozenPortionId)
        .firstOrNull;
    final correction = model.doseSourceCorrection;
    const available = '';
    final selected = correction != null
        ? correction.portionId ?? available
        : sameLot
        ? original?.id ?? available
        : null;
    final locale = regionalLocale.toString();
    return ListenableBuilder(
      listenable: model.draft.dose,
      builder: (context, _) {
        final dose = parseNumber(model.draft.dose.text);
        final destination = portions.where((p) => p.id == selected).firstOrNull;
        final oldCoffee = model.coffees
            .where((c) => c.id == brew.coffeeId)
            .firstOrNull;
        final newCoffee = model.coffees
            .where((c) => c.id == model.coffeeId)
            .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('dose-source-${model.lotId}'),
              initialValue: selected,
              decoration: InputDecoration(labelText: s.chooseDoseSource),
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: available,
                  child: Text(s.doseAvailableCoffee),
                ),
                for (final p in portions)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.label} · ${formatGrams(p.remainingGrams, locale)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  model.selectDoseSource(value == available ? null : value);
                }
              },
              validator: (value) {
                if (dose == null && value == null) return null;
                if (value == null) return s.doseSourceRequired;
                if (correction == null || destination == null) return null;
                if (dose == null) return s.brewFrozenNeedsDose;
                final credit = original?.id == destination.id
                    ? brew.frozenDoseGrams ?? 0
                    : 0;
                return dose > destination.remainingGrams + credit + 1e-6
                    ? s.dosePortionTooSmall
                    : null;
              },
            ),
            if (correction != null &&
                dose != null &&
                brew.doseGrams != null &&
                oldCoffee != null &&
                newCoffee != null)
              Text(
                s.doseSourceSummary(
                  formatGrams(brew.doseGrams!, locale),
                  oldCoffee.name,
                  formatGrams(dose, locale),
                  '${newCoffee.name} · ${destination?.label ?? s.doseAvailableCoffee}',
                ),
              ),
          ],
        );
      },
    );
  }
}
