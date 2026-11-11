import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

import 'support/audit_metrics.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('numeric fields retain values across regional formatter workloads', () async {
    final dispatcher = binding.platformDispatcher;
    addTearDown(dispatcher.clearLocaleTestValue);
    for (final locale in [
      const Locale('en', 'US'),
      const Locale('es', 'ES'),
      const Locale('ar', 'EG'),
      const Locale('en', 'US'),
    ]) {
      dispatcher.localeTestValue = locale;
      var total = 0.0;
      final measurement = await measure(() {
        total = 0;
        for (var i = 0; i < 5000; i++) {
          final value = (i % 1000) / 100;
          total += parseNumber(fieldNumber(value, decimals: 2))!;
          total += parseNumber(fieldExact(value))!;
          total += parseNumber(
            decimalInputFormatter
                .formatEditUpdate(
                  TextEditingValue.empty,
                  const TextEditingValue(text: '18.25'),
                )
                .text,
          )!;
          total += parseNumber(fieldDecimal('17.125'))!;
        }
      });
      expect(total, closeTo(226825, 0.000001));
      for (final (decimals, rounded) in [(0, 18.0), (1, 18.3), (3, 18.257)]) {
        expect(parseNumber(fieldNumber(18.257, decimals: decimals)), rounded);
      }
      expect(parseNumber(fieldExact(17.123456789)), 17.123456789);
      expect(fieldExact(null), '');
      expect(parseNumber('1,234.5'), isNull);
      stdout.writeln(
        'NUMERIC_FIELDS ${jsonEncode({'environment': 'host Flutter test; synchronous formatting/parsing', 'locale': locale.toString(), 'iterations': 5000, ...measurement})}',
      );
    }
  });
}
