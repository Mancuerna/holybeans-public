import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/data/services/meticulous_client.dart';

const connectedMachines = {'meticulous', 'gaggimate'};

String? trimOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String requireCatalogName(String name, String field) {
  final clean = name.trim();
  if (clean.isEmpty || clean.length > 120) {
    throw ArgumentError.value(name, field);
  }
  return clean;
}

String catalogNameKey(String name) => name.trim().toLowerCase();

void validateWaterProfileValues({
  required double? ghPpmAsCaCO3,
  required double? khPpmAsCaCO3,
  required double? tdsPpm,
  required double? ph,
}) {
  for (final entry in {
    'ghPpmAsCaCO3': ghPpmAsCaCO3,
    'khPpmAsCaCO3': khPpmAsCaCO3,
    'tdsPpm': tdsPpm,
  }.entries) {
    final value = entry.value;
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(value, entry.key);
    }
  }
  if (ph != null && (!ph.isFinite || ph < 0 || ph > 14)) {
    throw ArgumentError.value(ph, 'ph');
  }
}

/// A method's jug: its empty weight, and a name only alongside it.
(String?, double?) checkJug(String? name, double? grams) {
  if (grams == null) return (null, null);
  if (!grams.isFinite || grams <= 0 || grams > 10000) {
    throw ArgumentError.value(grams, 'vesselGrams');
  }
  final cleanName = trimOrNull(name);
  if (cleanName != null && cleanName.length > 120) {
    throw ArgumentError.value(name, 'vesselName');
  }
  return (cleanName, grams);
}

/// Validates a method's machine and address: the machine must be a known
/// one and its address a valid host, and there is no address without one.
(String?, String?) checkMachine(String? machine, String? address) {
  final cleanMachine = trimOrNull(machine);
  if (cleanMachine == null) return (null, null);
  if (!connectedMachines.contains(cleanMachine)) {
    throw ArgumentError.value(machine, 'machine');
  }
  final cleanAddress = trimOrNull(address);
  if (cleanAddress != null) {
    try {
      if (cleanMachine == 'gaggimate') {
        GaggimateClient.normalizeAddress(cleanAddress);
      } else {
        MeticulousClient.normalizeAddress(cleanAddress);
      }
    } on FormatException {
      throw ArgumentError.value(address, 'machineAddress');
    }
  }
  return (cleanMachine, cleanAddress);
}
