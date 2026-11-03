import 'package:flutter/material.dart';
import 'package:holybeans/data/preferences/water_target_settings.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/weight_targets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Keeps display choice local to the phone; the plan itself stays in the draft.
class FilterWaterTargets extends StatefulWidget {
  const FilterWaterTargets({
    super.key,
    required this.plan,
    required this.poured,
    required this.builder,
    this.openSettings = WaterTargetSettings.open,
  });
  final PourPlan plan;
  final double? poured;
  final Widget Function(List<WeightTarget>) builder;
  final Future<WaterTargetSettings> Function() openSettings;
  @override
  State<FilterWaterTargets> createState() => _FilterWaterTargetsState();
}

class _FilterWaterTargetsState extends State<FilterWaterTargets> {
  late final Future<WaterTargetSettings> settings = widget.openSettings();
  bool visible = true;
  bool saving = false;
  bool touched = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await (await settings).load();
      if (mounted && !touched) setState(() => visible = saved);
    } on Object {
      // If storage cannot be read, the display remains usable with its default.
    }
  }

  Future<void> _change(bool value) async {
    touched = true;
    setState(() {
      visible = value;
      saving = true;
    });
    try {
      await (await settings).save(value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.waterTargetsSaveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final format = NumberFormat('0.##', regionalLocale.toString());
    final steps = widget.plan.steps;
    final poured = widget.poured;
    final next = poured == null
        ? null
        : steps.where((step) => step.targetGrams > poured + .5).firstOrNull;
    final targets = [
      for (final step in steps)
        WeightTarget(
          grams: step.targetGrams,
          label:
              '${step.kind == PourStepKind.bloom ? '${s.bloomNumber(step.number)} · 1:${format.format(step.addGrams / widget.plan.doseGrams)}' : s.waterPlanPour(step.number)} · ${format.format(step.targetGrams)} g',
          active: step == next,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.waterTargetsShow,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Switch(
                key: const ValueKey('water-targets-toggle'),
                value: visible,
                onChanged: saving ? null : _change,
              ),
            ],
          ),
        ),
        widget.builder(visible ? targets : const []),
      ],
    );
  }
}
