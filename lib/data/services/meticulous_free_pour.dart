import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// A filter brew poured by hand over the Meticulous's scale in its "free
/// pour" mode, reduced to what a brew in HolyBeans can hold. The machine
/// keeps these apart from its espresso shots.
class MeticulousFreePour {
  const MeticulousFreePour({
    required this.id,
    required this.brewedAt,
    this.doseGrams,
    this.waterGrams,
    this.beverageGrams,
    this.temperatureC,
    this.timeSeconds,
    this.pours = const [],
    this.curve,
  });

  /// Builds a free pour from one record of the machine's pour-over history
  /// (`GET /api/v1/history/pour-over/files/<file>`).
  factory MeticulousFreePour.fromRecord(Map<String, Object?> record) {
    final id = record['id'];
    final startedAt = DateTime.tryParse('${record['startedAt']}');
    if (record['mode'] != 'free_pour' || id is! String || startedAt == null) {
      throw const FormatException('Not a free pour record');
    }
    final recipe = _map(record['recipe']);
    final measured = _map(record['measurements']);
    final durationMs = _number(measured['durationMs']);
    final pours = <DetectedPour>[
      for (final pour in _list(record['pours']).map(_map))
        if ((
              _number(pour['startTimeMs']),
              _number(pour['endTimeMs']),
              _number(pour['waterG']),
            )
            case (final start?, final end?, final grams?)
            when end >= start && grams > 0)
          DetectedPour(
            startMs: start.round(),
            endMs: end.round(),
            grams: grams.toDouble(),
          ),
    ];
    final times = <int>[];
    final flow = <double>[];
    final weight = <double>[];
    for (final sample in _list(record['samples']).map(_map)) {
      final time = _number(sample['t']);
      final grams = _number(sample['w']);
      if (time == null || grams == null) continue;
      times.add(time.round());
      weight.add(grams.toDouble());
      flow.add((_number(sample['f']) ?? 0).toDouble());
    }
    double? positive(Object? value) => switch (_number(value)) {
      final number? when number > 0 => (number * 10).round() / 10,
      _ => null,
    };
    return MeticulousFreePour(
      id: id,
      brewedAt: startedAt.toLocal(),
      doseGrams: positive(measured['doseG']) ?? positive(recipe['doseG']),
      waterGrams: positive(measured['waterPouredG']),
      beverageGrams: positive(measured['beverageG']),
      temperatureC:
          positive(measured['waterTemperatureC']) ??
          positive(recipe['temperatureC']),
      timeSeconds: durationMs == null || durationMs < 500
          ? null
          : (durationMs / 1000).round(),
      pours: pours,
      curve: times.length < 2
          ? null
          : ShotCurve(timesMs: times, flow: flow, weight: weight),
    );
  }

  /// The machine's record UUID, stable across requests.
  final String id;
  final DateTime brewedAt;
  final double? doseGrams;

  /// Water poured, as the scale measured it.
  final double? waterGrams;

  /// What ended up in the server.
  final double? beverageGrams;
  final double? temperatureC;
  final int? timeSeconds;

  /// The pours the machine told apart, with the water each one added.
  final List<DetectedPour> pours;

  /// Weight and flow (g/s) over time.
  final ShotCurve? curve;
}

/// The Meticulous a filter brew reads free pours from: that of any method
/// (an active one first), as its scale serves every filter method.
String? freePourMachineAddress(Iterable<BrewMethod> methods) {
  final machines = methods.where(
    (method) =>
        method.machine == 'meticulous' &&
        (method.machineAddress?.trim().isNotEmpty ?? false),
  );
  final machine =
      machines.where((method) => method.archivedAtMs == null).firstOrNull ??
      machines.firstOrNull;
  return machine?.machineAddress!.trim();
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

num? _number(Object? value) => switch (value) {
  final num number when number.isFinite => number,
  _ => null,
};
