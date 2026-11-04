import 'package:flutter/material.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/coffee_picker.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';
import 'package:intl/intl.dart';

class CuppingSetup extends StatelessWidget {
  const CuppingSetup({super.key, required this.model, required this.formKey});
  final CuppingModel model;
  final GlobalKey<FormState> formKey;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final d = model.draft;
    final number = NumberFormat('0.##', regionalLocale.toString());
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const ValueKey('cupping-blind'),
            contentPadding: EdgeInsets.zero,
            title: Text(s.cuppingBlind),
            subtitle: Text(s.cuppingBlindHint),
            value: d.blind,
            onChanged: model.busy ? null : model.setBlind,
          ),
          TextFormField(
            initialValue: d.name,
            maxLength: 120,
            decoration: InputDecoration(labelText: s.cuppingName),
            onChanged: (v) => model.change(() => d.name = v),
          ),
          Text(s.cuppingCommon, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          CuppingNumber(
            key: const ValueKey('cupping-dose'),
            label: '${s.dose} (g)',
            value: d.dose,
            max: 1000,
            onChanged: (v) => model.change(() => d.updateDose(v)),
          ),
          const SizedBox(height: 12),
          CuppingNumber(
            key: ValueKey(
              'cupping-water-${d.waterEdited ? "edited" : d.water}',
            ),
            label: '${s.water} (g)',
            value: d.water,
            max: 10000,
            onChanged: (v) => model.change(() {
              d.water = v;
              d.waterEdited = true;
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              s.cuppingRecommendation(number.format(d.suggestedCapacity)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          CuppingNumber(
            label: '${s.temperature} (°C)',
            value: d.temperature,
            max: 100,
            onChanged: (v) => model.change(() => d.temperature = v),
          ),
          const SizedBox(height: 12),
          CuppingEquipment(model: model),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.cuppingSound),
            value: d.sound,
            onChanged: (v) => model.change(() => d.sound = v),
          ),
          TextFormField(
            key: const ValueKey('cupping-crust-time'),
            initialValue: formatCuppingDuration(d.crustSeconds),
            decoration: InputDecoration(labelText: s.cuppingCrustTime),
            keyboardType: TextInputType.datetime,
            validator: (text) {
              final value = parseCuppingDuration(text ?? '');
              return value != null &&
                      value >= 60 &&
                      value <= 600 &&
                      value < d.tastingSeconds
                  ? null
                  : s.cuppingTimeError;
            },
            onChanged: (text) {
              final value = parseCuppingDuration(text);
              if (value != null &&
                  value >= 60 &&
                  value <= 600 &&
                  value < d.tastingSeconds) {
                model.change(() => d.crustSeconds = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('cupping-taste-time'),
            initialValue: formatCuppingDuration(d.tastingSeconds),
            decoration: InputDecoration(labelText: s.cuppingTasteTime),
            keyboardType: TextInputType.datetime,
            validator: (text) {
              final value = parseCuppingDuration(text ?? '');
              return value != null && value > d.crustSeconds && value <= 3600
                  ? null
                  : s.cuppingTimeError;
            },
            onChanged: (text) {
              final value = parseCuppingDuration(text);
              if (value != null && value > d.crustSeconds && value <= 3600) {
                model.change(() => d.tastingSeconds = value);
              }
            },
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < d.cups.length; i++)
            CuppingCupSetup(key: ObjectKey(d.cups[i]), model: model, index: i),
          if (d.cups.length < 6)
            OutlinedButton.icon(
              key: const ValueKey('cupping-add-cup'),
              onPressed: () =>
                  model.change(() => d.cups.add(CuppingCupDraft())),
              icon: const Icon(Icons.add),
              label: Text(s.cuppingAddCup),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class CuppingNumber extends StatelessWidget {
  const CuppingNumber({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  double? parse(String? text) => parseNumber(text ?? '');
  bool valid(double? v) => v != null && v.isFinite && v > 0 && v <= max;
  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: NumberFormat('0.##', regionalLocale.toString()).format(value),
    decoration: InputDecoration(labelText: label),
    inputFormatters: [decimalInputFormatter],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (text) => valid(parse(text))
        ? null
        : AppLocalizations.of(context)!.cuppingSetupError,
    onChanged: (text) {
      final v = parse(text);
      if (valid(v)) onChanged(v!);
    },
  );
}

class CuppingEquipment extends StatelessWidget {
  const CuppingEquipment({super.key, required this.model, this.cup});
  final CuppingModel model;
  final CuppingCupDraft? cup;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final d = model.draft;
    final c = cup;
    return Column(
      children: [
        if (c == null || !c.commonGrinder) ...[
          CuppingChoice(
            label: s.grinder,
            value: c == null ? d.grinderId : c.grinderId,
            choices: {
              for (final g in model.grinders)
                if (g.archivedAtMs == null) g.id: g.name,
            },
            none: s.preGround,
            onChanged: (v) => model.change(() {
              if (c == null) {
                d.grinderId = v;
              } else {
                c.grinderId = v;
              }
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(
              'grind-${c == null ? "common" : model.draft.cups.indexOf(c)}',
            ),
            initialValue: c == null ? d.grindSetting : c.grindSetting,
            maxLength: 120,
            decoration: InputDecoration(labelText: s.grindSetting),
            onChanged: (v) => model.change(() {
              if (c == null) {
                d.grindSetting = v;
              } else {
                c.grindSetting = v;
              }
            }),
          ),
        ],
        if (c == null || !c.commonWater) ...[
          const SizedBox(height: 12),
          CuppingChoice(
            label: s.waterProfile,
            value: c == null ? d.waterProfileId : c.waterProfileId,
            choices: {
              for (final w in model.waters)
                if (w.archivedAtMs == null) w.id: w.name,
            },
            none: s.noWaterProfile,
            onChanged: (v) => model.change(() {
              if (c == null) {
                d.waterProfileId = v;
              } else {
                c.waterProfileId = v;
              }
            }),
          ),
        ],
      ],
    );
  }
}

class CuppingCupSetup extends StatelessWidget {
  const CuppingCupSetup({
    super.key,
    required this.model,
    required this.index,
    this.identifying = false,
  });
  final CuppingModel model;
  final int index;
  final bool identifying;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final c = model.draft.cups[index];
    final lots = model.lots
        .where((l) => l.coffeeId == c.coffeeId && l.archivedAtMs == null)
        .toList();
    final n = NumberFormat('0.#', regionalLocale.toString());
    final sources = <String, String>{};
    for (var i = 0; i < lots.length; i++) {
      final lot = lots[i];
      final fresh = lot.remainingGrams == null
          ? null
          : (lot.remainingGrams! - (lot.overdrawGrams ?? 0)).clamp(
              0,
              double.infinity,
            );
      sources['lot:${lot.id}'] =
          '${lots.length > 1 ? "${i + 1}. " : ""}${fresh == null ? s.cuppingUnknownStock : s.cuppingFresh(n.format(fresh))}';
      for (final p in model.portions.where(
        (p) => p.lotId == lot.id && p.remainingGrams > 0,
      )) {
        sources['frozen:${p.id}'] = s.cuppingFrozen(
          n.format(p.remainingGrams),
          p.label,
        );
      }
    }
    final value = c.frozenPortionId == null
        ? (c.lotId == null ? null : 'lot:${c.lotId}')
        : 'frozen:${c.frozenPortionId}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cuppingCupLabel(model, index, s),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!identifying && model.draft.cups.length > 2)
                  IconButton(
                    tooltip: s.cuppingRemoveCup,
                    onPressed: () =>
                        model.change(() => model.draft.cups.removeAt(index)),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!model.draft.blind || identifying)
              CoffeePicker(
                key: ValueKey('cupping-coffee-$index'),
                repository: model.repository,
                coffees: model.coffees,
                includeArchived: false,
                label: s.beanName,
                value: c.coffeeId,
                onChanged: (v) => model.chooseCoffee(c, v),
              ),
            if ((!model.draft.blind || identifying) && sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              CuppingChoice(
                key: ValueKey('cupping-source-$index'),
                label: s.cuppingSource,
                value: value,
                choices: sources,
                onChanged: (v) => model.change(() {
                  if (v == null) return;
                  if (v.startsWith('lot:')) {
                    c.lotId = v.substring(4);
                    c.frozenPortionId = null;
                  } else {
                    c.frozenPortionId = v.substring(7);
                    c.lotId = model.portions
                        .firstWhere((p) => p.id == c.frozenPortionId)
                        .lotId;
                  }
                }),
              ),
            ],
            if (!identifying) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.cuppingCommonGrinder),
                value: c.commonGrinder,
                onChanged: (v) => model.change(() {
                  if (!v) {
                    c.grinderId = model.draft.grinderId;
                    c.grindSetting = model.draft.grindSetting;
                  }
                  c.commonGrinder = v;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.cuppingCommonWater),
                value: c.commonWater,
                onChanged: (v) => model.change(() {
                  if (!v) c.waterProfileId = model.draft.waterProfileId;
                  c.commonWater = v;
                }),
              ),
              CuppingEquipment(model: model, cup: c),
            ],
            if (identifying) ...[
              const SizedBox(height: 12),
              Text(
                '${s.rating}: ${c.notEvaluated[0] ? s.cuppingNotEvaluated : "${n.format(c.rating)} / 10"}',
              ),
              if (c.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(s.notes, style: Theme.of(context).textTheme.labelMedium),
                Text(
                  c.notes,
                  key: ValueKey('cupping-identification-notes-$index'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Rebuild the dropdown when its controlled selection changes, retaining
/// absent archived references visibly until the user selects a new value.
class CuppingChoice extends StatelessWidget {
  const CuppingChoice({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.none,
  });
  final String label;
  final String? value;
  final String? none;
  final Map<String, String> choices;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      if (none != null) DropdownMenuItem(child: Text(none!)),
      if (value != null && !choices.containsKey(value))
        DropdownMenuItem(
          value: value,
          child: Text(AppLocalizations.of(context)!.archivedStatus),
        ),
      for (final entry in choices.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(
            entry.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
  );
}
