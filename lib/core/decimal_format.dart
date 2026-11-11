import 'package:intl/intl.dart';

// Cached mutable intl objects stay private. Locale is part of every key so a
// device-region change cannot reuse the previous region's decimal separator.
final _formats = <(String, String, bool), NumberFormat>{};

/// Formats a decimal with an explicit pattern and locale.
String formatDecimal(
  num? value, {
  required String pattern,
  required String locale,
  bool grouping = true,
}) {
  final key = (pattern, locale, grouping);
  var format = _formats[key];
  if (format == null) {
    format = NumberFormat(pattern, locale);
    if (!grouping) format.turnOffGrouping();
    if (_formats.length >= 64) _formats.remove(_formats.keys.first);
    _formats[key] = format;
  }
  return format.format(value);
}
