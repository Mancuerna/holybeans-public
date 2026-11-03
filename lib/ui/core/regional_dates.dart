import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats a calendar date with the device locale, independently of the
/// language selected for HolyBeans.
String formatRegionalDate(DateTime date, Locale deviceLocale) =>
    DateFormat.yMd(deviceLocale.toString()).format(date);

/// A date and time in the device's regional format, e.g. "07/10/2026 14:54",
/// the same as brews and beans use, whatever language HolyBeans is in.
String formatRegionalDateTime(
  DateTime time,
  Locale deviceLocale, {
  bool includeSeconds = false,
}) =>
    '${formatRegionalDate(time, deviceLocale)} ${regionalTimeFormat(deviceLocale.toString(), includeSeconds: includeSeconds).format(time)}';

String formatRegionalTime(DateTime time, Locale deviceLocale) =>
    regionalTimeFormat(deviceLocale.toString()).format(time);

DateFormat regionalTimeFormat(
  String localeName, {
  bool includeSeconds = false,
}) => WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat
    ? (includeSeconds ? DateFormat.Hms(localeName) : DateFormat.Hm(localeName))
    : (includeSeconds ? DateFormat.jms(localeName) : DateFormat.jm(localeName));

/// The device's region, which numeric dates follow.
Locale get regionalLocale => WidgetsBinding.instance.platformDispatcher.locale;

/// Returns the local midnight starting the calendar day after [date].
///
/// Constructing the next date avoids a 24-hour duration shifting this
/// boundary across daylight-saving changes.
DateTime nextLocalDayStart(DateTime date) =>
    DateTime(date.year, date.month, date.day + 1);

/// Converts a calendar date to the stable, locale-independent value stored in
/// the database.
String formatIsoCalendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
