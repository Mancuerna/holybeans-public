import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/calendar_days.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/fingerprint.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/domain/statistics.dart';
import 'package:holybeans/domain/text_suggestions.dart';

void main() {
  test('median callers retain distinct even-window and empty contracts', () {
    expect(median([9, 1, 5, 3]), 4);
    expect(upperMedian([9, 1, 5, 3]), 5);
    expect(median([9, 1, 5]), 5);
    expect(median(const []), isNull);
    expect(() => upperMedian(const []), throwsRangeError);
    expect(() => pistonMedian(const []), throwsArgumentError);
    final values = [9.0, 1.0, 5.0, 3.0];
    expect(pistonMedian(values), 4);
    expect(values, [9, 1, 5, 3]);
  });

  test('FNV preserves byte hashing and both existing serialized forms', () {
    expect(fingerprintHex(fnv1a64(const [])), 'cbf29ce484222325');
    expect(fingerprintHex(fnv1a64(utf8.encode('hello'))), 'a430d84680aabd0b');
    for (final (source, bq, backup) in [
      ('', '-340d631b7bdddcdb', '7d0d901d480febc5'),
      ('hello', '-5bcf27b97f5542f5', 'c5f517c925a9f5e5'),
      ('café ☕', '1e9db3a4b5c684d4', '9eccf6a6c91c55c2'),
      ('{"name":"Etiopía"}', '-5ea2588602002b00', 'fa9a74e4121d8de0'),
    ]) {
      expect(bqFingerprint(source), bq);
      expect(
        journalDigest(
          jsonEncode({
            'data': {'v': source},
          }),
        ).fingerprint,
        backup,
      );
    }
  });

  test(
    'shared accent folding retains caller punctuation and mark policies',
    () {
      expect(
        foldCountryName('  São-Tomé...and-Príncipe '),
        'sao tome and principe',
      );
      expect(
        foldSuggestion('  São-Tomé...and-Príncipe '),
        'sao-tome...and-principe',
      );
      expect(foldCountryName('Cafe\u0301'), 'cafe\u0301');
      expect(foldSuggestion('Cafe\u0301'), 'cafe');
      expect(foldCountryName('café ☕'), 'cafe ☕');
      expect(foldSuggestion('\u0301 abc \u0301'), ' abc ');
      expect(FoldedTextMatcher('cafe').matches('☕ CAFE\u0301!'), isTrue);
    },
  );

  test(
    'calendar days use supplied dates, ignoring elapsed hours and UTC shifts',
    () {
      final before = DateTime(2026, 3, 28, 23, 59);
      final after = DateTime(2026, 3, 29, 0, 1);
      expect(calendarDaysBetween(before, after), 1);
      expect(calendarDaysBetween(after, before), -1);
      expect(
        calendarDaysBetween(DateTime(2026, 3, 29), DateTime(2026, 3, 30)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 10, 25), DateTime(2026, 10, 26)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime.utc(2026, 3, 29), DateTime(2026, 3, 29)),
        0,
      );
    },
  );

  test('decimal cache separates locale, precision and grouping contracts', () {
    expect(
      formatDecimal(1234.56, pattern: '#,##0.00', locale: 'en_GB'),
      '1,234.56',
    );
    expect(
      formatDecimal(1234.56, pattern: '#,##0.00', locale: 'es_ES'),
      '1.234,56',
    );
    expect(
      formatDecimal(
        1234.56,
        pattern: '#,##0.00',
        locale: 'en_GB',
        grouping: false,
      ),
      '1234.56',
    );
    expect(
      formatDecimal(1234.56, pattern: '#,##0.00', locale: 'en_GB'),
      '1,234.56',
    );
    expect(formatDecimal(1.25, pattern: '0.0', locale: 'en_GB'), '1.3');
    expect(formatDecimal(1.25, pattern: '0.00', locale: 'en_GB'), '1.25');
    for (var digits = 1; digits < 70; digits++) {
      formatDecimal(1, pattern: '0${' ' * digits}', locale: 'en_GB');
    }
    expect(
      formatDecimal(1234.56, pattern: '#,##0.00', locale: 'es_ES'),
      '1.234,56',
    );
  });
}
