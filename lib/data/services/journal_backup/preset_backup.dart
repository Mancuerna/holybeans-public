part of '../journal_backup.dart';

extension on _RestoredJournal {
  void _checkPresets() {
    final ids = <String>{};
    for (final p in equipmentPresets) {
      if (!ids.add(p.id) ||
          p.name.trim().isEmpty ||
          p.name.length > 120 ||
          !_methodsById.containsKey(p.methodId) ||
          (p.grinderId != null && !_grindersById.containsKey(p.grinderId)) ||
          (p.waterProfileId != null &&
              !_waterProfilesById.containsKey(p.waterProfileId))) {
        throw const FormatException('Invalid equipment preset');
      }
    }
    final links = <(String, String)>{};
    for (final t in presetTools) {
      if (!ids.contains(t.presetId) ||
          !_toolsById.containsKey(t.toolId) ||
          !links.add((t.presetId, t.toolId))) {
        throw const FormatException('Invalid equipment preset tool');
      }
    }
    for (final brew in brews) {
      if (brew.equipmentPresetId != null &&
          !ids.contains(brew.equipmentPresetId)) {
        throw const FormatException('Missing brew equipment preset');
      }
    }
  }
}
