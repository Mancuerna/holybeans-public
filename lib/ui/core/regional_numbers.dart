import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Formats numbers without grouping, following changes to the device region.
class RegionalNumberFormat {
  RegionalNumberFormat(this.pattern);

  final String pattern;
  String? _locale;
  late NumberFormat _format;

  String format(num value) {
    final locale = regionalLocale.toString();
    if (_locale != locale) {
      _format = NumberFormat(pattern, locale)..turnOffGrouping();
      _locale = locale;
    }
    return _format.format(value);
  }
}
