import 'package:flutter/material.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/coffee_origin_draft.dart';
import 'package:holybeans/ui/core/coffee_country_field.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/suggested_text_field.dart';

/// One origin of a coffee in its form: country (with suggestions), region,
/// variety, process, farm, producer, altitude and harvest.
class CoffeeOriginCard extends StatelessWidget {
  const CoffeeOriginCard({
    super.key,
    required this.origin,
    required this.index,
    required this.onRemove,
    required this.onChanged,
    this.suggestions,
    this.onMoveUp,
    this.onMoveDown,
  });

  final CoffeeOriginDraft origin;
  final CoffeeSuggestions? suggestions;
  final int index;
  final VoidCallback onRemove;

  /// Called when the country changes, to refresh its flag.
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        // Filled fields need room between them: in dark themes each one
        // has its own background against the card.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _OriginHeader(
              index: index,
              onRemove: onRemove,
              onMoveUp: onMoveUp,
              onMoveDown: onMoveDown,
            ),
            CoffeeCountryField(
              controller: origin.country,
              focusNode: origin.countryFocus,
              onChanged: onChanged,
            ),
            SuggestedTextField(
              suggestions: suggestions?.regions ?? const [],
              controller: origin.region,
              decoration: InputDecoration(labelText: s.region),
            ),
            SuggestedTextField(
              suggestions: suggestions?.varieties ?? const [],
              controller: origin.variety,
              decoration: InputDecoration(labelText: s.variety),
            ),
            SuggestedTextField(
              suggestions: suggestions?.processes ?? const [],
              controller: origin.process,
              decoration: InputDecoration(labelText: s.process),
            ),
            SuggestedTextField(
              suggestions: suggestions?.farms ?? const [],
              controller: origin.farm,
              decoration: InputDecoration(labelText: s.farm),
            ),
            SuggestedTextField(
              suggestions: suggestions?.producers ?? const [],
              controller: origin.producer,
              decoration: InputDecoration(labelText: s.producer),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: numberField(
                    context,
                    origin.altitude,
                    s.altitude,
                    key: ValueKey('coffee-origin-altitude-$index'),
                    integer: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: numberField(
                    context,
                    origin.altitudeMax,
                    s.altitudeMax,
                    key: ValueKey('coffee-origin-altitude-max-$index'),
                    integer: true,
                    helperText: s.altitudeMaxHint,
                    validate: (value) =>
                        validAltitudeRange(
                          int.tryParse(origin.altitude.text.trim()),
                          value?.round(),
                        )
                        ? null
                        : s.invalidAltitudeRange,
                  ),
                ),
              ],
            ),
            SuggestedTextField(
              suggestions: suggestions?.harvests ?? const [],
              fieldKey: ValueKey('coffee-origin-harvest-${origin.key}'),
              controller: origin.harvest,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: s.harvest,
                hintText: s.harvestHint,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The origin's number, with the buttons that move or remove it.
class _OriginHeader extends StatelessWidget {
  const _OriginHeader({
    required this.index,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final int index;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            s.originNumber(index + 1),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (onMoveUp != null)
          IconButton(
            tooltip: s.moveOriginUp,
            visualDensity: VisualDensity.compact,
            onPressed: () => onMoveUp!(),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        if (onMoveDown != null)
          IconButton(
            tooltip: s.moveOriginDown,
            visualDensity: VisualDensity.compact,
            onPressed: () => onMoveDown!(),
            icon: const Icon(Icons.arrow_downward_rounded),
          ),
        IconButton(
          tooltip: s.removeOrigin,
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}
