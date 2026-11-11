import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

/// Formats numbers without grouping, following changes to the device region.
class RegionalNumberFormat {
  RegionalNumberFormat(this.pattern);

  final String pattern;

  String format(num value) => formatDecimal(
    value,
    pattern: pattern,
    locale: regionalLocale.toString(),
    grouping: false,
  );
}
