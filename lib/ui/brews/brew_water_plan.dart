import 'package:flutter/material.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/water_plan_timer.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// A folded water plan whose amounts can fill empty details when saving.
class BrewWaterPlan extends StatefulWidget {
  const BrewWaterPlan({
    super.key,
    required this.draft,
    required this.dose,
    required this.water,
    required this.timer,
    this.scale,
    this.waterTarget,
    this.showTimer = false,
    this.bloom,
  });
  final BrewPoursDraft draft;
  final TextEditingController dose;
  final TextEditingController water;
  final BrewTimer timer;
  final BrewScaleSession? scale;
  final double? Function()? waterTarget;
  final bool showTimer;
  final TextEditingController? bloom;

  @override
  State<BrewWaterPlan> createState() => _BrewWaterPlanState();
}

class _BrewWaterPlanState extends State<BrewWaterPlan> {
  final _readingKey = GlobalKey();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.draft,
      widget.dose,
      widget.water,
      widget.timer,
      if (widget.scale != null) widget.scale!.scale,
    ]),
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final draft = widget.draft;
      final dose = parseNumber(widget.dose.text);
      final water =
          widget.waterTarget?.call() ?? parseNumber(widget.water.text);
      final blooms = draft.bloomCount;
      final number = NumberFormat('0.#', regionalLocale.toString());
      final plan = draft.waterPlan(dose: dose, water: water);
      final valid = plan != null && plan.problem == null;
      final steps = valid ? plan.steps : <PourStep>[];
      final poured = widget.scale?.pouredGrams;
      final next = widget.timer.running && poured != null
          ? steps.where((step) => step.targetGrams > poured + .5).firstOrNull
          : null;
      return ExpansionTile(
        key: const ValueKey('brew-water-plan'),
        initiallyExpanded: draft.waterPlanExpanded,
        onExpansionChanged: draft.expandWaterPlan,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 12),
        title: Text(
          water != null && water > 0
              ? '${s.waterPlanTitle} · ${number.format(water)} g'
              : s.waterPlanTitle,
        ),
        subtitle: next == null
            ? null
            : Text(s.pourTo(number.format(next.targetGrams))),
        children: [
          if (blooms != null && blooms > 0)
            DropdownButtonFormField<double>(
              key: const ValueKey('water-plan-bloom-ratio'),
              initialValue: draft.waterPlanBloomRatio,
              decoration: InputDecoration(labelText: s.waterPlanBloomRatio),
              items: [
                for (final ratio in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0])
                  DropdownMenuItem(
                    value: ratio,
                    child: Text('1:${number.format(ratio)}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  draft.setWaterPlanBloomRatio(value);
                }
              },
            ),
          const SizedBox(height: 8),
          if (!valid)
            Text(
              plan?.problem == PourPlanProblem.bloomWater
                  ? s.pourProblemBloomWater
                  : s.waterPlanNeedsRecipe,
            )
          else
            Column(
              key: _readingKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showTimer)
                  WaterPlanTimer(
                    timer: widget.timer,
                    bloom: blooms != null && blooms > 0 ? widget.bloom : null,
                    readingKey: _readingKey,
                  ),
                Table(
                  key: const ValueKey('water-plan-table'),
                  columnWidths: const {0: FlexColumnWidth(1.4)},
                  children: [
                    TableRow(
                      children:
                          [
                                s.waterPlanPhase,
                                s.waterPlanAdded,
                                s.waterPlanCumulative,
                              ]
                              .map(
                                (text) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    text,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    for (final step in steps)
                      TableRow(
                        children:
                            [
                                  step.kind == PourStepKind.bloom
                                      ? '${s.bloomNumber(step.number)} · 1:${number.format(step.addGrams / dose!)}'
                                      : s.waterPlanPour(step.number),
                                  '${number.format(step.addGrams)} g',
                                  '${number.format(step.targetGrams)} g',
                                ]
                                .map(
                                  (text) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Text(text),
                                  ),
                                )
                                .toList(),
                      ),
                  ],
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.waterPlanHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    },
  );
}
