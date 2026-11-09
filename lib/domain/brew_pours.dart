import 'dart:convert';

enum BrewPourKind { bloom, pour }

/// A recorded pour, with water optionally supplied by the chosen plan.
class BrewPourPhase {
  factory BrewPourPhase.fromJson(Map<String, dynamic> json) {
    if (json['number'] is! int ||
        (json['waterGrams'] != null && json['waterGrams'] is! num) ||
        (json['durationSeconds'] != null && json['durationSeconds'] is! int) ||
        (json['restSeconds'] != null && json['restSeconds'] is! int) ||
        (json['waterFromPlan'] != null && json['waterFromPlan'] is! bool)) {
      throw const FormatException('Invalid pour measurements');
    }
    final kind = BrewPourKind.values
        .where((v) => v.name == json['kind'])
        .firstOrNull;
    if (kind == null) throw const FormatException('Invalid pour kind');
    return BrewPourPhase(
      kind: kind,
      number: json['number'] as int,
      waterGrams: (json['waterGrams'] as num?)?.toDouble(),
      waterFromPlan: json['waterFromPlan'] == true,
      durationSeconds: json['durationSeconds'] as int?,
      restSeconds: json['restSeconds'] as int?,
    );
  }
  const BrewPourPhase({
    required this.kind,
    required this.number,
    this.waterGrams,
    this.waterFromPlan = false,
    this.durationSeconds,
    this.restSeconds,
  });

  final BrewPourKind kind;
  final int number;
  final double? waterGrams;

  /// Whether the water comes from Water Breakdown rather than a measurement.
  final bool waterFromPlan;
  final int? durationSeconds;

  /// Rest after a bloom, separate from time spent pouring.
  final int? restSeconds;

  /// How fast the water went in, from its amount and pouring time.
  double? get flowGramsPerSecond => switch ((waterGrams, durationSeconds)) {
    (final grams?, final seconds?) when seconds > 0 && !waterFromPlan =>
      grams / seconds,
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'number': number,
    'waterGrams': waterGrams,
    if (waterFromPlan) 'waterFromPlan': true,
    'durationSeconds': durationSeconds,
    'restSeconds': restSeconds,
  };
}

/// Nullable counts mean unrecorded; zero explicitly records no blooms/pours.
class BrewPours {
  factory BrewPours.fromStorage({
    int? bloomCount,
    int? pourCount,
    String? phasesJson,
  }) {
    final raw = phasesJson == null ? <dynamic>[] : jsonDecode(phasesJson);
    if (raw is! List) throw const FormatException('Invalid pour phases');
    final phases = raw.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid pour phase');
      }
      return BrewPourPhase.fromJson(value);
    }).toList();
    return BrewPours(
      bloomCount: bloomCount,
      pourCount: pourCount,
      phases: phases,
    );
  }
  BrewPours({
    this.bloomCount,
    this.pourCount,
    List<BrewPourPhase> phases = const [],
  }) : phases = List.unmodifiable(phases) {
    validate();
  }

  static const maxBlooms = 3;
  static const maxPours = 10;
  final int? bloomCount;

  /// Ordinary pours, excluding blooms.
  final int? pourCount;
  final List<BrewPourPhase> phases;

  /// The sum of recorded bloom pouring and resting times, in seconds.
  int get bloomSeconds => phases
      .where((phase) => phase.kind == BrewPourKind.bloom)
      .fold(
        0,
        (sum, phase) =>
            sum + (phase.durationSeconds ?? 0) + (phase.restSeconds ?? 0),
      );

  void validate() {
    for (final (count, max) in [
      (bloomCount, maxBlooms),
      (pourCount, maxPours),
    ]) {
      if (count != null && (count < 0 || count > max)) {
        throw const FormatException('Invalid pour count');
      }
    }
    final keys = <(BrewPourKind, int)>{};
    for (final phase in phases) {
      final count = phase.kind == BrewPourKind.bloom ? bloomCount : pourCount;
      if (count == null ||
          phase.number < 1 ||
          phase.number > count ||
          !keys.add((phase.kind, phase.number))) {
        throw const FormatException('Pour phase does not match its count');
      }
      if (phase.waterFromPlan && phase.waterGrams == null) {
        throw const FormatException('Planned water needs an amount');
      }
      if (phase.waterGrams case final grams?) {
        if (!grams.isFinite || grams <= 0) {
          throw const FormatException('Invalid pour water');
        }
      }
      for (final seconds in [phase.durationSeconds, phase.restSeconds]) {
        if (seconds != null && seconds <= 0) {
          throw const FormatException('Invalid pour duration');
        }
      }
      if (phase.kind != BrewPourKind.bloom && phase.restSeconds != null) {
        throw const FormatException('Only blooms have a rest time');
      }
    }
  }

  String? get phasesJson => phases.isEmpty
      ? null
      : jsonEncode(phases.map((v) => v.toJson()).toList());
}
