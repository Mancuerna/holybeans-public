import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en_GB'));

  test('calendar dates use the device region and retain ISO storage', () {
    final date = DateTime(2026, 9, 28);

    final us = formatRegionalDate(date, const Locale('en', 'US'));
    final uk = formatRegionalDate(date, const Locale('en', 'GB'));

    expect(us, DateFormat.yMd('en_US').format(date));
    expect(uk, DateFormat.yMd('en_GB').format(date));
    expect(us, isNot(uk));
    expect(formatIsoCalendarDate(date), '2026-09-28');
  });

  test('next local day boundary follows calendar dates across DST changes', () {
    final springDate = DateTime(2026, 3, 29);
    final springEnd = nextLocalDayStart(springDate);
    expect(springEnd, DateTime(2026, 3, 30));

    final autumnDate = DateTime(2026, 10, 25);
    final autumnEnd = nextLocalDayStart(autumnDate);
    expect(autumnEnd, DateTime(2026, 10, 26));

    if (Platform.environment['TZ'] == 'Europe/Madrid') {
      expect(springDate.add(const Duration(days: 1)), DateTime(2026, 3, 30, 1));
      expect(
        DateTime(2026, 3, 30, 0, 30).isBefore(springEnd),
        isFalse,
        reason: 'A brew after local midnight belongs to the next date.',
      );

      expect(
        autumnDate.add(const Duration(days: 1)),
        DateTime(2026, 10, 25, 23),
      );
      expect(
        DateTime(2026, 10, 25, 23, 30).isBefore(autumnEnd),
        isTrue,
        reason: 'The repeated final hour still belongs to the selected date.',
      );
    }
  });
}
