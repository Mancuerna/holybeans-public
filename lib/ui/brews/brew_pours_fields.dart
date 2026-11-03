import 'package:flutter/material.dart';
import 'package:holybeans/domain/bloom_water_ratio.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_fields.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Bloom and pour counts with their folded details. Each part can be hidden
/// in Settings; hidden values are kept in [draft] and saved.
class BrewPoursFields extends StatelessWidget {
  const BrewPoursFields({
    super.key,
    required this.draft,
    this.bloomTime,
    this.dose,
    this.showBlooms = true,
    this.showPours = true,
    this.showDetails = true,
  });
  final BrewPoursDraft draft;
  final TextEditingController? dose;

  /// The total bloom time, or null when hidden.
  final TextEditingController? bloomTime;
  final bool showBlooms;
  final bool showPours;
  final bool showDetails;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      Widget count(BrewPourKind kind, int? value, int max, String label) =>
          DropdownButtonFormField<int>(
            key: ValueKey('brew-${kind.name}-count-$value'),
            initialValue: value ?? -1,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem(value: -1, child: Text(s.poursUnrecorded)),
              for (var n = 0; n <= max; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (n) => draft.setCount(kind, n == -1 ? null : n),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldPair(
            showBlooms
                ? count(
                    BrewPourKind.bloom,
                    draft.bloomCount,
                    BrewPours.maxBlooms,
                    s.bloomCount,
                  )
                : null,
            showPours
                ? count(
                    BrewPourKind.pour,
                    draft.pourCount,
                    BrewPours.maxPours,
                    s.pourCount,
                  )
                : null,
          ),
          if (showBlooms || showPours)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.pourCountHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (draft.fromCurve)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                key: const ValueKey('pours-from-curve'),
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.poursFromCurve,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('pours-from-curve-undo'),
                    onPressed: draft.undoFromCurve,
                    child: Text(s.undo),
                  ),
                ],
              ),
            ),
          if ((showDetails &&
                  (draft.bloomCount ?? 0) + (draft.pourCount ?? 0) > 0) ||
              (draft.bloomCount != 0 && bloomTime != null))
            ExpansionTile(
              key: const ValueKey('brew-pour-details'),
              controller: draft.detailsController,
              onExpansionChanged: (value) => draft.detailsExpanded = value,
              tilePadding: EdgeInsets.zero,
              title: Text(s.pourDetails),
              children: [
                if (draft.bloomCount != 0 && bloomTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    child: IntegerField(
                      key: const ValueKey('brew-bloom'),
                      controller: bloomTime!,
                      label: s.bloomTotalSeconds,
                    ),
                  ),
                for (final kind in BrewPourKind.values)
                  if (showDetails)
                    for (
                      var n = 1;
                      n <=
                          (kind == BrewPourKind.bloom
                              ? draft.bloomCount ?? 0
                              : draft.pourCount ?? 0);
                      n++
                    )
                      _phase(context, kind, n),
              ],
            ),
        ],
      );
    },
  );

  Widget _phase(BuildContext context, BrewPourKind kind, int number) {
    final s = AppLocalizations.of(context)!;
    final phase = draft.phaseDraft(kind, number);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kind == BrewPourKind.bloom
                ? s.bloomNumber(number)
                : s.pourNumber(number),
          ),
          const SizedBox(height: 16),
          numberField(
            context,
            phase.water,
            s.pourWaterGrams,
            key: ValueKey('${kind.name}-$number-water'),
          ),
          ListenableBuilder(
            listenable: phase.water,
            builder: (context, _) => phase.waterFromPlan
                ? Text(
                    s.pourWaterFromPlan,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : const SizedBox.shrink(),
          ),
          if (kind == BrewPourKind.bloom && dose != null)
            ListenableBuilder(
              listenable: Listenable.merge([phase.water, dose]),
              builder: (context, _) {
                final ratio = bloomWaterRatio(
                  parseNumber(phase.water.text),
                  parseNumber(dose!.text),
                );
                return ratio == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, left: 12),
                        child: Text(
                          s.waterPlanBloomRatioValue(
                            NumberFormat(
                              '0.##',
                              regionalLocale.toString(),
                            ).format(ratio),
                          ),
                        ),
                      );
              },
            ),
          const SizedBox(height: 20),
          IntegerField(
            key: ValueKey('${kind.name}-$number-duration'),
            controller: phase.duration,
            label: s.pourDurationSeconds,
          ),
          // Worked out as they are typed.
          ListenableBuilder(
            listenable: Listenable.merge([phase.water, phase.duration]),
            builder: (context, _) => switch (phase
                .value(kind, number)
                .flowGramsPerSecond) {
              final flow? => Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  s.pourFlowHint(
                    NumberFormat('0.0', regionalLocale.toString()).format(flow),
                  ),
                  key: ValueKey('${kind.name}-$number-flow'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              null => const SizedBox.shrink(),
            },
          ),
          if (kind == BrewPourKind.bloom) ...[
            const SizedBox(height: 20),
            IntegerField(
              key: ValueKey('bloom-$number-rest'),
              controller: phase.rest,
              label: s.bloomRestSeconds,
            ),
          ],
        ],
      ),
    );
  }
}

class BrewPourDetails extends StatelessWidget {
  const BrewPourDetails({super.key, required this.pours, this.doseGrams});
  final BrewPours pours;
  final double? doseGrams;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.##', regionalLocale.toString());
    return ExpansionTile(
      key: const ValueKey('brew-recorded-pour-details'),
      tilePadding: EdgeInsets.zero,
      title: Text(s.pourDetails),
      children: [
        for (final phase in pours.phases)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              phase.kind == BrewPourKind.bloom
                  ? s.bloomNumber(phase.number)
                  : s.pourNumber(phase.number),
            ),
            subtitle: Text(
              [
                if (phase.waterGrams case final grams?)
                  s.pourWaterValue(number.format(grams)),
                if (phase.waterFromPlan) s.pourWaterFromPlan,
                if (phase.kind == BrewPourKind.bloom)
                  if (bloomWaterRatio(phase.waterGrams, doseGrams)
                      case final ratio?)
                    s.waterPlanBloomRatioValue(number.format(ratio)),
                if (phase.durationSeconds case final seconds?)
                  s.pourDurationValue(seconds),
                if (phase.flowGramsPerSecond case final flow?)
                  s.pourFlowValue(
                    NumberFormat('0.0', regionalLocale.toString()).format(flow),
                  ),
                if (phase.restSeconds case final seconds?)
                  s.bloomRestValue(seconds),
              ].join(', '),
            ),
          ),
      ],
    );
  }
}
