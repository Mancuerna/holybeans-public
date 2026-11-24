import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';

class BrewPresetPicker extends StatelessWidget {
  const BrewPresetPicker({super.key, required this.model});
  final BrewFormModel model;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final selected = model.selectedPreset;
    return DropdownButtonFormField<String>(
      key: ValueKey(('equipment-preset', selected?.preset.id)),
      initialValue: selected?.preset.id ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: s.equipmentPreset),
      items: [
        DropdownMenuItem(value: '', child: Text(s.none)),
        if (selected != null &&
            !model.presetChoices.any((p) => p.preset.id == selected.preset.id))
          DropdownMenuItem(
            value: selected.preset.id,
            enabled: false,
            child: Text(s.equipmentPresetUnavailable),
          ),
        for (final p in model.presetChoices)
          DropdownMenuItem(value: p.preset.id, child: Text(p.preset.name)),
      ],
      onChanged: model.saving
          ? null
          : (id) => model.selectPreset(
              model.presetChoices.where((p) => p.preset.id == id).firstOrNull,
            ),
    );
  }
}
