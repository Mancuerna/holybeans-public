enum EquipmentDeletionBlocker {
  brews,
  tools,
  machine,
  recipient,
  cupping,
  methods,
  presets,
}

class EquipmentInUseException implements Exception {
  EquipmentInUseException(Iterable<EquipmentDeletionBlocker> blockers)
    : blockers = List.unmodifiable(blockers);

  final List<EquipmentDeletionBlocker> blockers;
}
