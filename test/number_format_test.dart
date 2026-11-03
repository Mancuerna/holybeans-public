import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/core/formatters.dart';

void main() {
  test(
    'large amounts and altitudes omit grouping but retain decimal notation',
    () {
      expect(formatEuro(12345.67, 'en'), '€12345.67');
      expect(formatEuro(12345.67, 'es'), '12345,67\u00a0€');
      const origin = CoffeeComponent(
        id: 'o',
        coffeeId: 'c',
        position: 0,
        altitudeMeters: 1800,
      );
      expect(originDetails([origin], 'en'), '1800 m');
      expect(originDetails([origin], 'es'), '1800 m');
    },
  );

  test('cafe currency follows the region and keeps unknown codes readable', () {
    expect(formatCafeCurrency(4.5, 'USD', 'en_US'), '\$4.50');
    expect(formatCafeCurrency(4.5, 'EUR', 'en_US'), '€4.50');
    expect(formatCafeCurrency(4.5, 'EUR', 'es_ES'), '4,50\u00a0€');
    expect(formatCafeCurrency(4.5, 'USD', 'es_ES'), '4,50\u00a0\$');
    expect(formatCafeCurrency(4.5, 'EUR', 'es_MX'), '€4.50');
    expect(formatCafeCurrency(4.5, 'XYZ', 'en_US'), 'XYZ\u00a04.50');
    expect(formatCafeCurrency(4.5, 'XYZ', 'es_ES'), '4,50\u00a0XYZ');
  });
}
