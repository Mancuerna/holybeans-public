/// Linear interpolation on ordered timestamps, holding the endpoints outside
/// the recorded interval. Empty series stay empty.
List<double> resampleCurveSeries(
  List<int> times,
  List<double> values,
  List<int> target,
) {
  if (values.isEmpty || times.isEmpty) return const [];
  var index = 0;
  final result = <double>[];
  for (final time in target) {
    while (index + 1 < times.length && times[index + 1] <= time) {
      index++;
    }
    if (time <= times.first) {
      result.add(values.first);
    } else if (index + 1 == times.length) {
      result.add(values.last);
    } else {
      final gap = times[index + 1] - times[index];
      final fraction = gap <= 0 ? 0.0 : (time - times[index]) / gap;
      result.add(
        values[index] + fraction * (values[index + 1] - values[index]),
      );
    }
  }
  return result;
}
