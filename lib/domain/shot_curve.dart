import 'dart:convert';
import 'dart:math' as math;

import 'package:holybeans/domain/axis_ticks.dart';

/// One quantity recorded along a shot.
enum CurveSeries { weight, flow, pressure }

/// Measurements of a brew over time, as recorded by a connected machine
/// (pressure in bar, flow in ml/s and weight in the cup in g) or a scale
/// (weight and its flow in g/s, no pressure). Times are milliseconds from
/// the start of the extraction. A series a device does not measure is
/// empty.
class ShotCurve {
  factory ShotCurve.fromJson(String source) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Curve is not an object');
    List<num> list(String key, {bool optional = false}) {
      final value = json[key];
      if (optional && value == null) return const [];
      if (value is! List || value.any((item) => item is! num)) {
        throw FormatException('Curve series $key is invalid');
      }
      return value.cast<num>();
    }

    final times = list('t');
    // Scale data can be absent when a machine recorded pressure only.
    final pressure = list('p', optional: true);
    final flow = list('f', optional: true);
    final weight = list('w');
    if ((weight.isNotEmpty && weight.length != times.length) ||
        [
          pressure,
          flow,
        ].any((values) => values.isNotEmpty && values.length != times.length)) {
      throw const FormatException('Curve series differ in length');
    }
    return ShotCurve(
      timesMs: [for (final time in times) time.round()],
      pressure: [for (final value in pressure) value.toDouble()],
      flow: [for (final value in flow) value.toDouble()],
      weight: [for (final value in weight) value.toDouble()],
    );
  }
  ShotCurve({
    required this.timesMs,
    this.pressure = const [],
    required this.flow,
    required this.weight,
  }) : assert(
         [
           pressure,
           flow,
           weight,
         ].every((values) => values.isEmpty || values.length == timesMs.length),
       );

  final List<int> timesMs;
  final List<double> pressure;
  final List<double> flow;
  final List<double> weight;

  bool get isEmpty => timesMs.isEmpty;

  /// The series this curve has values for, in the usual order.
  List<CurveSeries> get series => [
    for (final series in CurveSeries.values)
      if (timesMs.isNotEmpty && values(series).isNotEmpty) series,
  ];
  int get durationMs => timesMs.isEmpty ? 0 : timesMs.last;

  List<double> values(CurveSeries series) => switch (series) {
    CurveSeries.weight => weight,
    CurveSeries.flow => flow,
    CurveSeries.pressure => pressure,
  };

  double maxOf(CurveSeries series) => values(series).fold(0, math.max);

  /// The highest value to scale a chart and report a peak by: [maxOf]
  /// without a few isolated spikes (see [robustRange]).
  double peakOf(CurveSeries series) =>
      math.max(0, robustRange(values(series)).high);

  /// Index of the sample closest to [timeMs].
  int indexAt(int timeMs) {
    if (timesMs.isEmpty) return -1;
    var low = 0;
    var high = timesMs.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (timesMs[mid] < timeMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 &&
        (timeMs - timesMs[low - 1]).abs() < (timesMs[low] - timeMs).abs()) {
      return low - 1;
    }
    return low;
  }

  /// The same shot with each series smoothed by a Gaussian over time
  /// ([sigmaMs] wide), for drawing. Machines report values in small steps
  /// and with sample-to-sample jitter; this keeps the shape (ramps, the
  /// pressure plateau, the drop at the end) without the staircase. Weights
  /// beyond three sigmas are ignored, and samples need not be evenly spaced.
  ShotCurve smoothed({int sigmaMs = 400}) {
    if (timesMs.length < 3 || sigmaMs <= 0) return this;
    final reach = 3 * sigmaMs;
    final twoSigmaSquared = 2.0 * sigmaMs * sigmaMs;
    List<double> smooth(List<double> values) {
      final result = List<double>.filled(values.length, 0);
      var first = 0;
      for (var i = 0; i < values.length; i++) {
        final time = timesMs[i];
        while (timesMs[first] < time - reach) {
          first++;
        }
        var sum = 0.0;
        var total = 0.0;
        for (var j = first; j < values.length; j++) {
          final distance = timesMs[j] - time;
          if (distance > reach) break;
          final weight = math.exp(-distance * distance / twoSigmaSquared);
          sum += values[j] * weight;
          total += weight;
        }
        result[i] = sum / total;
      }
      return result;
    }

    return ShotCurve(
      timesMs: timesMs,
      pressure: smooth(pressure),
      flow: smooth(flow),
      weight: smooth(weight),
    );
  }

  /// Compact JSON: one array per series, values with two decimals. A
  /// series the device does not measure is left out.
  String toJson() {
    List<num> round(List<double> values) => [
      for (final value in values) (value * 100).round() / 100,
    ];
    return jsonEncode({
      't': timesMs,
      if (pressure.isNotEmpty) 'p': round(pressure),
      if (flow.isNotEmpty) 'f': round(flow),
      'w': round(weight),
    });
  }
}
