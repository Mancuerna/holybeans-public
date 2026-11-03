import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/freeze_plan.dart';

void main() {
  test('nine exact portions and decimal weights conserve total', () {
    expect(
      FreezePlan(
        totalGrams: 900,
        portionGrams: 100,
      ).amounts(includeRemainder: true),
      List.filled(9, 100),
    );
    final plan = FreezePlan(totalGrams: 0.3, portionGrams: 0.1);
    expect(plan.count, 3);
    expect(plan.remainder, 0);
  });
  test('remainder can be frozen or left available', () {
    final plan = FreezePlan(totalGrams: 950, portionGrams: 100);
    expect(plan.count, 9);
    expect(plan.remainder, 50);
    expect(
      plan.amounts(includeRemainder: true).fold(0.0, (a, b) => a + b),
      950,
    );
    expect(
      plan.amounts(includeRemainder: false).fold(0.0, (a, b) => a + b),
      900,
    );
  });
  test('invalid and impractical divisions are rejected', () {
    for (final weight in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      1001.0,
      0.0001,
      0.001,
    ]) {
      expect(
        () => FreezePlan(totalGrams: 900, portionGrams: weight),
        throwsArgumentError,
      );
    }
  });
  test('only the missing fresh dose is requested', () {
    expect(frozenGramsNeeded(18, 0), 18);
    expect(frozenGramsNeeded(18, 5), 13);
    expect(frozenGramsNeeded(18, 20), 0);
    expect(frozenGramsNeeded(null, 0), 0);
    expect(frozenGramsNeeded(18, null), 0);
  });
}
