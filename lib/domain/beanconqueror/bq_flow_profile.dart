import 'package:holybeans/domain/shot_curve.dart';

/// Reads a BeanConqueror flow profile (`brews/<uuid>_flow_profile.json`):
/// what a connected scale or machine recorded during a brew. Its series
/// (`weight`, `realtimeFlow`, `pressureFlow`…) are lists of samples, each
/// with the clock time it was taken (`timestamp`, "HH:mm:ss.SSS"). Times
/// come from those clocks, which every source fills; `brew_time` is empty
/// for machine shots.
///
/// The curve follows the weight samples; flow (g/s) and pressure (bar)
/// take the sample nearest in time. Pressure is kept only when some sample
/// has it. Returns null when there are fewer than two weight samples.
ShotCurve? bqFlowCurve(Object? json) {
  if (json is! Map) return null;
  final weight = _samples(json['weight'], const [
    'actual_weight',
    'not_mutated_weight',
  ]);
  if (weight.length < 2) return null;
  final flow = _samples(json['realtimeFlow'], const ['flow_value']);
  final pressure = _samples(json['pressureFlow'], const ['actual_pressure']);

  // Clock times that roll past midnight keep counting.
  final start = weight.first.ms;
  int since(int ms) =>
      ms < start - 3600000 ? ms + 86400000 - start : ms - start;

  final times = <int>[];
  final grams = <double>[];
  for (final sample in weight) {
    final ms = since(sample.ms);
    if (times.isNotEmpty && ms <= times.last) continue;
    times.add(ms);
    grams.add(sample.value);
  }
  if (times.length < 2) return null;

  List<double> along(List<_Sample> series) {
    if (series.isEmpty) return const [];
    final points = [for (final s in series) (since(s.ms), s.value)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    var at = 0;
    return [
      for (final time in times)
        () {
          while (at + 1 < points.length &&
              (points[at + 1].$1 - time).abs() <=
                  (points[at].$1 - time).abs()) {
            at++;
          }
          return points[at].$2;
        }(),
    ];
  }

  final pressures = along(pressure);
  return ShotCurve(
    timesMs: times,
    weight: grams,
    flow: along(flow),
    pressure: pressures.any((bar) => bar > 0) ? pressures : const [],
  );
}

class _Sample {
  const _Sample(this.ms, this.value);

  final int ms;
  final double value;
}

/// The samples of [series] with a readable clock time, reading the first
/// of [fields] that holds a number.
List<_Sample> _samples(Object? series, List<String> fields) => [
  if (series is List)
    for (final entry in series)
      if (entry is Map)
        if (_clockMs(entry['timestamp']) case final ms?)
          if (fields.map((field) => entry[field]).whereType<num>().firstOrNull
              case final value? when value.isFinite)
            _Sample(ms, value.toDouble()),
];

/// Milliseconds since midnight of "HH:mm:ss.SSS".
int? _clockMs(Object? timestamp) {
  if (timestamp is! String) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$')
      .firstMatch(timestamp.trim());
  if (match == null) return null;
  final fraction = (match.group(4) ?? '0').padRight(3, '0');
  return ((int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) * 60 +
              int.parse(match.group(3)!)) *
          1000 +
      int.parse(fraction);
}
