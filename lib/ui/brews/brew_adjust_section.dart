import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/step_value.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// A number field with − and + beside it, for the values that change by a
/// small step from one brew to the next. The field stays editable; the
/// buttons are off when the text is not a plain number ("18 clicks").
class StepField extends StatelessWidget {
  const StepField({
    super.key,
    required this.controller,
    required this.label,
    this.step,
    this.previous,
    this.stepKey,
  });

  final TextEditingController controller;
  final String label;

  /// Fixed step; by default the last digit written.
  final double? step;

  /// The starting recipe value, shown under the field.
  final String? previous;

  /// Prefix for the keys of the field and its buttons.
  final String? stepKey;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        String? stepped(int direction) => stepNumberText(
          plainNumberText(controller.text),
          direction,
          step: step,
        );
        void apply(int direction) {
          final next = stepped(direction);
          if (next == null) return;
          controller.text = fieldDecimal(next.replaceAll(',', '.'));
          HapticFeedback.selectionClick();
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: stepKey == null ? null : ValueKey('$stepKey-field'),
                controller: controller,
                inputFormatters: [decimalInputFormatter],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: label,
                  helperText: previous == null
                      ? null
                      : s.adjustPrevious(previous!),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton.filledTonal(
                key: stepKey == null ? null : ValueKey('$stepKey-less'),
                tooltip: s.adjustLess(label),
                onPressed: stepped(-1) == null ? null : () => apply(-1),
                icon: const Icon(Icons.remove_rounded),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton.filledTonal(
                key: stepKey == null ? null : ValueKey('$stepKey-more'),
                tooltip: s.adjustMore(label),
                onPressed: stepped(1) == null ? null : () => apply(1),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What usually changes when a brew is tuned: grind, dose, water (filter)
/// and temperature, each with its starting recipe value under it. The rest of
/// the form folds below it.
class BrewAdjustSection extends StatelessWidget {
  const BrewAdjustSection({super.key, required this.model, this.seed});

  final BrewFormModel model;

  /// The brew being tuned, for the previous values.
  final Brew? seed;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final draft = model.draft;
    final number = NumberFormat('0.##', regionalLocale.toString());
    String? grams(double? value) =>
        value == null ? null : '${number.format(value)} g';
    return Column(
      key: const ValueKey('brew-adjust-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!model.isPreGround && model.shows(BrewParameter.grindSetting)) ...[
          StepField(
            stepKey: 'adjust-grind',
            controller: draft.grindSetting,
            label: s.grindSetting,
            previous: seed?.grindSetting,
          ),
          const SizedBox(height: 16),
        ],
        StepField(
          stepKey: 'adjust-dose',
          controller: draft.dose,
          label: '${s.dose} (g)',
          step: 0.1,
          previous: grams(seed?.doseGrams),
        ),
        if (model.isEspresso && model.shows(BrewParameter.ratio)) ...[
          const SizedBox(height: 16),
          brewRatioControl(model),
        ],
        if (!model.isEspresso && model.shows(BrewParameter.water)) ...[
          const SizedBox(height: 16),
          StepField(
            stepKey: 'adjust-water',
            controller: draft.water,
            label: '${s.water} (g)',
            step: 1,
            previous: grams(seed?.waterGrams),
          ),
        ],
        if (!model.isEspresso) ...[
          const SizedBox(height: 16),
          BrewPoursSection(model: model),
        ],
        if (model.shows(BrewParameter.temperature)) ...[
          const SizedBox(height: 16),
          StepField(
            stepKey: 'adjust-temperature',
            controller: draft.temperature,
            label: '${s.temperature} (°C)',
            step: 1,
            previous: seed?.temperatureC == null
                ? null
                : '${number.format(seed!.temperatureC)} °C',
          ),
        ],
      ],
    );
  }
}
