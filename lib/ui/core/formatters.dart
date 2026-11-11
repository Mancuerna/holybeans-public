import 'package:flutter/widgets.dart' show Locale;
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/journal_codes.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Euro amounts without thousands separators, keeping local decimal notation.
NumberFormat euroNumberFormat(String localeName) => NumberFormat.currency(
  locale: localeName,
  name: 'EUR',
  symbol: '€',
  decimalDigits: 2,
)..turnOffGrouping();

String formatEuro(double amount, String localeName) =>
    euroNumberFormat(localeName).format(amount);

String formatCafeCurrency(
  double amount,
  String currencyCode,
  String localeName,
) {
  final code = currencyCode.trim().toUpperCase();
  final format = NumberFormat.simpleCurrency(locale: localeName, name: code);
  if (format.currencySymbol != code) return format.format(amount);
  return NumberFormat.currency(
    locale: localeName,
    name: code,
    symbol: '$code\u00a0',
  ).format(amount).trim();
}

/// Date and time of a brew in the device's regional format.
String formatBrewTimestamp(Brew brew, Locale deviceLocale) =>
    formatRegionalDateTime(
      DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs),
      deviceLocale,
    );

/// Minutes and seconds, e.g. "2:35".
String formatDuration(int totalSeconds) =>
    '${totalSeconds ~/ 60}:${(totalSeconds % 60).toString().padLeft(2, '0')}';

/// A time-axis tick as the rest of the app writes times ("0:05", "−0:02"),
/// or in seconds when it falls between whole seconds.
String formatTimeTick(double seconds, NumberFormat number) {
  final whole = seconds.roundToDouble();
  if ((seconds - whole).abs() > 1e-6) return '${number.format(seconds)} s';
  return '${whole < 0 ? '−' : ''}${formatDuration(whole.abs().round())}';
}

/// A form label without its unit suffix, e.g. "Paid price (€)" → "Paid
/// price", for detail rows that show the unit with the value.
String beanDetailLabel(String label) =>
    label.replaceFirst(RegExp(r'\s*\((?:g|€)\)$'), '');

String roastLevelLabel(AppLocalizations strings, String code) =>
    switch (RoastLevel.fromCode(code)) {
      RoastLevel.dark => strings.roastDark,
      RoastLevel.medium => strings.roastMedium,
      RoastLevel.omni => strings.roastOmni,
      RoastLevel.light => strings.roastLight,
      RoastLevel.ultraLight => strings.roastUltraLight,
      null => code,
    };
