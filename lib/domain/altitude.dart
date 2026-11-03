/// A recorded altitude, optionally with the upper end of a range, in metres.
bool validAltitudeRange(int? altitude, int? upper) =>
    (altitude == null || altitude > 0) &&
    (upper == null || (altitude != null && upper >= altitude));

String? altitudeLabel(int? altitude, int? upper) => altitude == null
    ? null
    : upper == null || upper == altitude
    ? '$altitude m'
    : '$altitude–$upper m';

/// Reads a single value or an explicit range, preserving both endpoints.
/// Grouped thousands and common metre units are accepted; invalid or reversed
/// ranges are not changed into invented values.
(int, int?)? parseAltitude(Object? value) {
  if (value is num) {
    if (!value.isFinite || value != value.roundToDouble() || value <= 0) {
      return null;
    }
    return (value.toInt(), null);
  }
  if (value is! String) return null;
  const number = r'(\d{1,3}(?:[.,]\d{3})+|\d+)';
  final match = RegExp(
    '^\\s*$number(?:\\s*(?:-|–|—|to|a)\\s*$number)?'
    r'\s*(?:m|msnm|masl|m\.a\.s\.l\.?)?\s*$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  int metres(String text) => int.parse(text.replaceAll(RegExp('[.,]'), ''));
  final low = metres(match.group(1)!);
  final high = match.group(2) == null ? null : metres(match.group(2)!);
  if (!validAltitudeRange(low, high)) return null;
  return (low, high == low ? null : high);
}
