/// The middle value, averaging the central pair; null for empty input.
double? median(Iterable<num> values) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// The upper middle value. Empty input retains the indexing error contract.
double upperMedian(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}
