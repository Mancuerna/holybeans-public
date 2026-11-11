import 'package:holybeans/domain/shot_curve.dart';

/// A completed machine recording. Flow is weighed flow (g/s), not pump flow.
class GaggimateShot {
  const GaggimateShot({
    required this.id,
    required this.machineAddress,
    required this.brewedAt,
    required this.profileName,
    required this.timeSeconds,
    this.yieldGrams,
    this.temperatureC,
    this.peakPressureBar,
    this.firstDripSeconds,
    this.doseGrams,
    this.grindSetting,
    this.notes,
    this.curve,
  });

  final String id;
  final String machineAddress;
  final DateTime brewedAt;
  final String profileName;
  final int timeSeconds;
  final double? yieldGrams;
  final double? temperatureC;
  final double? peakPressureBar;
  final int? firstDripSeconds;
  final double? doseGrams;
  final String? grindSetting;
  final String? notes;
  final ShotCurve? curve;

  // Numeric ids belong to one machine and may restart after storage is reset.
  String get externalId => gaggimateExternalId(machineAddress, id, brewedAt);
}

String gaggimateExternalId(String address, String id, DateTime date) =>
    '$address|$id|${date.millisecondsSinceEpoch}';

class GaggimateHistoryEntry {
  const GaggimateHistoryEntry({
    required this.id,
    required this.brewedAt,
    required this.profileName,
    required this.durationMs,
  });

  final String id;
  final DateTime brewedAt;
  final String profileName;
  final int durationMs;
}
