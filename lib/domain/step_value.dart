/// One step up or down from a number written in a field, kept in the way it
/// was written: "0.5" → "0.6", "7,5" → "7,6", "18" → "19", "23.25" → "23.3"
/// with a 0.1 step.
///
/// [step] defaults to the last written digit (0.1 for "0.5", 1 for "18").
/// Returns null when [text] is not a plain number (e.g. "18 clicks" or
/// "2.1.3"), so the field is left as it is; never goes below [min].
String? stepNumberText(
  String text,
  int direction, {
  double? step,
  double min = 0,
}) {
  final written = text.trim();
  final match = RegExp(r'^(\d+)(?:([.,])(\d+))?$').firstMatch(written);
  final empty = written.isEmpty;
  if (match == null && !empty) return null;
  final separator = match?.group(2) ?? '.';
  final writtenDecimals = match?.group(3)?.length ?? 0;
  final unit = step ?? _pow10(-writtenDecimals);
  // A given step shows its own precision ("17.9", "17"); a step taken from
  // the text keeps the decimals written ("1.0" stays a one-decimal grind).
  final decimals = step == null ? writtenDecimals : _decimalsOf(unit);
  final keep = step == null ? writtenDecimals : 0;
  final value = empty ? 0.0 : double.parse(written.replaceAll(',', '.'));
  // The next point of the step's grid in that direction, so 23.25 + 0.1
  // reads 23.3, not 23.35.
  final position = value / unit;
  final index = direction > 0
      ? (position + 1e-9).floor() + 1
      : (position - 1e-9).ceil() - 1;
  var next = index * unit;
  if (next < min) next = min;
  final shown = _trimZeros(next.toStringAsFixed(decimals), keep);
  return separator == ',' ? shown.replaceAll('.', ',') : shown;
}

double _pow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent.abs(); i++) {
    value = exponent < 0 ? value / 10 : value * 10;
  }
  return value;
}

int _decimalsOf(double step) {
  for (var decimals = 0; decimals < 6; decimals++) {
    final scaled = step * _pow10(decimals);
    if ((scaled - scaled.roundToDouble()).abs() < 1e-9) return decimals;
  }
  return 6;
}

/// Drops trailing zeros beyond [keep] decimals ("17.0" → "17" with none to
/// keep, "1.0" stays with one).
String _trimZeros(String fixed, int keep) {
  if (!fixed.contains('.')) return fixed;
  var trimmed = fixed;
  while (trimmed.endsWith('0') &&
      trimmed.length - trimmed.indexOf('.') - 1 > keep) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}
