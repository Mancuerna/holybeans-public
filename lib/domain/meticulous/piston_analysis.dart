// Retraction selection adapted from ha-meticulous (MIT), hessius and
// contributors. See assets/licenses/meticulous-piston.txt.
import 'dart:math' as math;

const pistonAlgorithmVersion = 1;

class PistonReading {
  const PistonReading({
    required this.shotId,
    required this.timeMs,
    required this.samples,
    this.current,
    this.speed,
  });
  final String shotId;
  final int timeMs;
  final int samples;
  final double? current;
  final double? speed;
  bool get usable => current != null && speed != null;
}

class PistonService {
  const PistonService({
    required this.id,
    required this.timeMs,
    required this.kind,
    this.notes = '',
  });
  final String id;
  final int timeMs;
  final String kind;
  final String notes;
  static const kinds = {'grease', 'descale', 'clean'};
}

double? pistonNumber(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  return number != null && number.isFinite ? number : null;
}

double pistonMedian(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw ArgumentError('Empty median');
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

PistonReading analyzePiston(Map<String, dynamic> entry) {
  final id = entry['id'];
  final time = pistonNumber(entry['time']);
  if (id is! String || id.isEmpty || time == null || time < 0) {
    throw const FormatException('Invalid shot identity');
  }
  const excluded = {
    '',
    'unknown',
    'idle',
    'click to start',
    'heating',
    'preheating',
    'starting...',
    'boot',
    'home',
    'purge',
    'finished',
  };
  String? state;
  String? before;
  final currents = <double>[];
  final speeds = <double>[];
  final rows = entry['data'] ?? const <Object?>[];
  if (rows is! List) throw const FormatException('Invalid shot data');
  for (final row in rows) {
    if (row is! Map ||
        row['status'] is! String ||
        (row['status'] as String).trim().isEmpty) {
      state = before = null;
      continue;
    }
    final status = (row['status'] as String)
        .replaceAll('_', ' ')
        .trim()
        .toLowerCase();
    if (status != state) {
      before = state;
      state = status;
    }
    if (state != 'retracting' || before == null || excluded.contains(before)) {
      continue;
    }
    final sensors = row['sensors'];
    final shot = row['shot'];
    if (sensors is! Map || shot is! Map) continue;
    final position = pistonNumber(sensors['motor_position']);
    final speed = pistonNumber(sensors['motor_speed']);
    final drive = pistonNumber(sensors['motor_power']);
    final current = pistonNumber(sensors['motor_current']);
    final pressure = pistonNumber(shot['pressure']);
    if (position == null ||
        speed == null ||
        drive == null ||
        current == null ||
        pressure == null) {
      continue;
    }
    if (drive <= -99 &&
        speed <= -8 &&
        pressure.abs() < .1 &&
        position >= 35 &&
        position <= 55) {
      currents.add(current.abs());
      speeds.add(speed.abs());
    }
  }
  return PistonReading(
    shotId: id,
    timeMs: (time * 1000).round(),
    samples: currents.length,
    current: currents.length < 5
        ? null
        : (pistonMedian(currents) * 1000).round() / 1000,
    speed: speeds.length < 5
        ? null
        : (pistonMedian(speeds) * 100).round() / 100,
  );
}

class PistonPoint {
  const PistonPoint(this.timeMs, this.value, this.raw, this.cycle);
  final int timeMs;
  final double value;
  final double raw;
  final int cycle;
}

List<PistonPoint> pistonSeries(
  List<PistonReading> readings,
  List<PistonService> services, {
  bool speed = false,
}) {
  final sorted = readings.where((r) => r.usable).toList()
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final marks = services.map((s) => s.timeMs).toList()..sort();
  final result = <PistonPoint>[];
  var left = 0;
  for (var i = 0; i < sorted.length; i++) {
    final row = sorted[i];
    final cycle = marks.where((t) => t <= row.timeMs).lastOrNull ?? 0;
    final start = math.max(
      cycle,
      row.timeMs - const Duration(days: 7).inMilliseconds,
    );
    while (left < i && sorted[left].timeMs < start) {
      left++;
    }
    double value(PistonReading r) => speed ? r.speed! : r.current!;
    result.add(
      PistonPoint(
        row.timeMs,
        pistonMedian(sorted.sublist(left, i + 1).map(value)),
        value(row),
        cycle,
      ),
    );
  }
  return List.unmodifiable(result);
}

({double? level, double? change, double? monthly}) pistonTrend(
  List<PistonReading> readings,
  List<PistonService> services,
) {
  final latestService = services.map((s) => s.timeMs).fold<int>(0, math.max);
  final series = pistonSeries(
    readings,
    services,
  ).where((p) => p.timeMs >= latestService).toList();
  if (series.isEmpty) return (level: null, change: null, monthly: null);
  final last = series.last;
  final start = last.cycle > 0
      ? last.cycle
      : last.timeMs - const Duration(days: 60).inMilliseconds;
  final rows = series.where((p) => p.timeMs >= start).toList();
  if (rows.length < 3) return (level: last.value, change: null, monthly: null);
  final baseline = pistonMedian(
    rows
        .where(
          (p) =>
              p.timeMs <=
              rows.first.timeMs + const Duration(days: 7).inMilliseconds,
        )
        .map((p) => p.raw),
  );
  final change = baseline > 0 ? (last.value / baseline - 1) * 100 : null;
  double? monthly;
  if (rows.length >= 5 &&
      rows.last.timeMs - rows.first.timeMs >=
          const Duration(days: 3).inMilliseconds &&
      baseline > 0) {
    final xs = rows
        .map(
          (p) => (p.timeMs - rows.first.timeMs) / Duration.millisecondsPerDay,
        )
        .toList();
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = rows.map((p) => p.raw).reduce((a, b) => a + b) / rows.length;
    var xx = 0.0;
    var xy = 0.0;
    for (var i = 0; i < rows.length; i++) {
      xx += math.pow(xs[i] - mx, 2);
      xy += (xs[i] - mx) * (rows[i].raw - my);
    }
    if (xx > 0) monthly = xy / xx * 30 / baseline * 100;
  }
  return (level: last.value, change: change, monthly: monthly);
}
