import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/water_calculator_fields.dart';
import 'package:holybeans/ui/equipment/water_calculator_model.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';

class WaterCalculatorInputs extends StatelessWidget {
  const WaterCalculatorInputs({
    super.key,
    required this.model,
    required this.savedProfiles,
  });
  final WaterCalculatorModel model;
  final List<WaterProfile> savedProfiles;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(context, s.waterStartingSection),
        _base(s),
        const SizedBox(height: 20),
        _heading(context, s.waterSaltsSection),
        Text(s.waterAvailableSaltsHint),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final salt in WaterSalt.values.where(
              model.availableSalts.contains,
            ))
              InputChip(
                key: ValueKey('water-selected-${salt.name}'),
                label: Text(saltLabel(s, salt)),
                deleteIcon: Icon(
                  Icons.close,
                  key: ValueKey('water-remove-${salt.name}'),
                ),
                onDeleted: () => model.setSalt(salt, false),
              ),
          ],
        ),
        if (model.availableSalts.length < WaterSalt.values.length)
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<WaterSalt>(
              key: const ValueKey('water-add-salt'),
              tooltip: s.waterAddSalt,
              onSelected: (salt) => model.setSalt(salt, true),
              itemBuilder: (_) => [
                for (final salt in WaterSalt.values.where(
                  (s) => !model.availableSalts.contains(s),
                ))
                  PopupMenuItem(value: salt, child: Text(saltLabel(s, salt))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '+ ${s.waterAddSalt}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        if (model.availableSalts.contains(WaterSalt.calciumChloride)) ...[
          const SizedBox(height: 12),
          _calciumForm(s),
        ],
        const SizedBox(height: 24),
        _heading(context, s.waterModeSection),
        DropdownButtonFormField<WaterCalculationMode>(
          key: const ValueKey('water-mode'),
          initialValue: model.mode,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.waterCalculator),
          items: [
            DropdownMenuItem(
              value: WaterCalculationMode.quantities,
              child: Text(s.waterQuantitiesMode),
            ),
            DropdownMenuItem(
              value: WaterCalculationMode.custom,
              child: Text(s.waterCustomMode),
            ),
            DropdownMenuItem(
              value: WaterCalculationMode.preset,
              child: Text(s.waterPresetMode),
            ),
          ],
          onChanged: (mode) {
            if (mode != null) model.chooseMode(mode);
          },
        ),
        const SizedBox(height: 16),
        switch (model.mode) {
          WaterCalculationMode.quantities => _quantities(s),
          WaterCalculationMode.custom => _target(s),
          WaterCalculationMode.preset => _presets(context, s),
        },
      ],
    );
  }

  Widget _heading(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _base(AppLocalizations s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('water-distilled'),
            label: Text(s.waterDistilled),
            selected: !model.mineralWater,
            onSelected: (_) {
              model.mineralWater = false;
              model.useSavedWater = false;
              model.recalculate();
            },
          ),
          ChoiceChip(
            key: const ValueKey('water-mineral'),
            label: Text(s.waterMineralBottle),
            selected: model.mineralWater && !model.useSavedWater,
            onSelected: (_) {
              model.mineralWater = true;
              model.useSavedWater = false;
              model.recalculate();
            },
          ),
          if (savedProfiles.isNotEmpty)
            ChoiceChip(
              key: const ValueKey('water-saved-source'),
              label: Text(s.waterSavedSource),
              selected: model.mineralWater && model.useSavedWater,
              onSelected: (_) {
                final profile =
                    savedProfiles
                        .where((p) => p.id == model.savedBaseId)
                        .firstOrNull ??
                    savedProfiles.first;
                model.useWater(profile);
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      waterInput(
        model.litres,
        s.waterFinalLitres,
        s,
        key: 'water-litres',
        positive: true,
        maximum: 10000,
      ),
      if (model.mineralWater && model.useSavedWater) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('water-saved-base-${model.savedBaseId}'),
          initialValue: model.savedBaseId,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.waterSavedBase),
          items: [
            for (final p in savedProfiles)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (id) {
            if (id != null) {
              model.useWater(savedProfiles.singleWhere((p) => p.id == id));
            }
          },
        ),
      ],
      const SizedBox(height: 16),
      Text(
        s.waterInitialComposition,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (model.mineralWater)
        WaterCompositionInputs(
          ions: model.ions,
          kh: model.baseKh,
          gh: model.baseGh,
          prefix: 'water-base',
        )
      else
        Text(s.waterDistilledComposition),
      if (model.initialComposition?.calculatedGh != null)
        WaterDerivedValues(water: model.initialComposition!),
    ],
  );

  Widget _calciumForm(AppLocalizations s) =>
      DropdownButtonFormField<CalciumForm>(
        key: const ValueKey('water-calcium-form'),
        initialValue: model.calcium,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.waterCalciumForm),
        items: [
          DropdownMenuItem(
            value: CalciumForm.anhydrous,
            child: Text(s.waterCalciumAnhydrous),
          ),
          DropdownMenuItem(
            value: CalciumForm.dihydrate,
            child: Text(s.waterCalciumDihydrate),
          ),
        ],
        onChanged: (form) {
          if (form != null) {
            model.calcium = form;
            model.recalculate();
          }
        },
      );

  Widget _quantities(AppLocalizations s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(s.waterDirectHint),
      const SizedBox(height: 12),
      for (final salt in WaterSalt.values.where(model.availableSalts.contains))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: waterInput(
            model.amounts[salt]!,
            '${saltLabel(s, salt)} (g)',
            s,
            key: 'water-amount-${salt.name}',
            maximum: 100000,
          ),
        ),
      if (model.availableSalts.isEmpty) Text(s.waterNoSalts),
    ],
  );

  Widget _target(AppLocalizations s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('water-target-ions'),
            label: Text(s.waterIonTarget),
            selected: model.ionTargets,
            onSelected: (_) {
              model.ionTargets = true;
              model.recalculate();
            },
          ),
          ChoiceChip(
            key: const ValueKey('water-target-gh-mode'),
            label: Text(s.waterGhTarget),
            selected: !model.ionTargets,
            onSelected: (_) {
              model.ionTargets = false;
              model.recalculate();
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        s.waterDesiredComposition,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (model.ionTargets) ...[
        Text(s.waterTargetPriorityHint),
        const SizedBox(height: 12),
        WaterCompositionInputs(
          ions: model.targetIons,
          kh: model.targetKh,
          prefix: 'water-target',
          target: true,
        ),
      ] else
        _ghFields(s),
    ],
  );

  Widget _presets(BuildContext context, AppLocalizations s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: const ValueKey('water-preset'),
        menuMaxHeight: 360,
        initialValue: model.targetSelection,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.waterTarget),
        items: [
          DropdownMenuItem<String>(
            enabled: false,
            child: Text(s.waterReferenceTargets),
          ),
          for (final preset in WaterPreset.values)
            DropdownMenuItem(
              value: 'preset:${preset.name}',
              child: Text(
                presetLabel(s, preset),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (savedProfiles.isNotEmpty || model.isSavedTarget)
            DropdownMenuItem<String>(
              enabled: false,
              child: Text(s.waterMyTargets),
            ),
          for (final profile in savedProfiles)
            DropdownMenuItem(
              value: 'water:${profile.id}',
              child: Text(
                profile.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (model.isSavedTarget &&
              !savedProfiles.any((p) => p.id == model.savedTargetId))
            DropdownMenuItem(
              value: model.targetSelection,
              child: Text(model.savedTargetName ?? s.waterSavedTarget),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          for (final preset in WaterPreset.values) {
            if (value == 'preset:${preset.name}') {
              model.choosePreset(preset);
              return;
            }
          }
          for (final profile in savedProfiles) {
            if (value == 'water:${profile.id}') {
              model.useTarget(profile);
              return;
            }
          }
        },
      ),
      if (!model.isSavedTarget)
        if (presetHint(s, model.preset) case final hint?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
      if (model.missingPresetSalts.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '${s.waterMissingRecipeSalts}: ${model.missingPresetSalts.map((salt) => saltLabel(s, salt)).join(', ')}',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('water-use-recipe-salts'),
            onPressed: model.usePresetSalts,
            child: Text(s.waterUseRecipeSalts),
          ),
        ),
      ],
    ],
  );
  Widget _ghFields(AppLocalizations s) => Column(
    children: [
      waterInput(model.targetGh, s.waterHardness, s, key: 'water-target-gh'),
      const SizedBox(height: 12),
      waterInput(model.targetKh, s.waterAlkalinity, s, key: 'water-target-kh'),
      const SizedBox(height: 12),
      SwitchListTile(
        key: const ValueKey('water-mixture'),
        contentPadding: EdgeInsets.zero,
        title: Text(s.waterMixture),
        value: model.mixHardness,
        onChanged: (value) {
          model.mixHardness = value;
          if (value) model.availableSalts.add(WaterSalt.calciumChloride);
          if (value && model.ghSource == WaterSalt.calciumChloride) {
            model.ghSource = WaterSalt.epsom;
          }
          model.recalculate();
        },
      ),
      if (model.mixHardness) ...[
        waterInput(
          model.calciumPercent,
          s.waterCalciumPercent,
          s,
          key: 'water-calcium-percent',
          maximum: 100,
        ),
        const SizedBox(height: 8),
        Text(s.waterMixtureHint),
        const SizedBox(height: 12),
      ],
      _source(s, true),
      const SizedBox(height: 12),
      _source(s, false),
    ],
  );

  Widget _source(AppLocalizations s, bool hardness) =>
      DropdownButtonFormField<WaterSalt>(
        key: ValueKey('water-source-$hardness-${model.mixHardness}'),
        initialValue: hardness ? model.ghSource : model.khSource,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: hardness
              ? (model.mixHardness ? s.waterMagnesiumSource : s.waterGhSource)
              : s.waterKhSource,
        ),
        items: [
          for (final salt in WaterSalt.values.where(
            (s) =>
                hardness ? s.index < (model.mixHardness ? 2 : 3) : s.index >= 3,
          ))
            DropdownMenuItem(
              value: salt,
              child: Text(saltLabel(s, salt), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (salt) {
          if (salt == null) return;
          if (hardness) {
            model.ghSource = salt;
            model.availableSalts.add(salt);
          } else {
            model.khSource = salt;
            model.availableSalts.add(salt);
          }
          model.recalculate();
        },
      );
}
