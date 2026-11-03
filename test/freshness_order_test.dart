import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/freshness_order.dart';

void main() {
  const window = FreshnessWindow(
    primeStart: 5,
    primeEnd: 15,
    goodUntil: 20,
    agingUntil: 30,
  );
  FreshnessToday at(int day, {FreshnessWindow limits = window}) => (
    day: day,
    phase: limits.phaseAt(day),
    window: limits,
    style: BrewStyle.filter,
  );

  test('use-soon order follows phases, then time left in each phase', () {
    final values = [
      for (final day in [2, 10, 33, 18, 25, 40, 14, 4]) at(day),
    ];
    values.sort((a, b) => compareFreshness(a, b, ascending: false));
    expect(values.map((value) => value.day), [40, 33, 25, 18, 14, 10, 4, 2]);
    values.sort((a, b) => compareFreshness(a, b, ascending: true));
    expect(values.map((value) => value.day), [2, 4, 10, 14, 18, 25, 33, 40]);
  });

  test('different roast windows use remaining time, not raw age', () {
    final younger = at(14);
    final older = at(
      20,
      limits: const FreshnessWindow(
        primeStart: 10,
        primeEnd: 30,
        goodUntil: 40,
        agingUntil: 50,
      ),
    );
    expect(compareFreshness(younger, older, ascending: false), isNegative);
    expect(compareFreshness(younger, older, ascending: true), isPositive);
    expect(compareFreshness(younger, at(14), ascending: false), 0);
  });

  test('unknown freshness always comes last, including reversed order', () {
    for (final ascending in [true, false]) {
      expect(compareFreshness(null, at(10), ascending: ascending), isPositive);
      expect(compareFreshness(at(10), null, ascending: ascending), isNegative);
      expect(compareFreshness(null, null, ascending: ascending), 0);
    }
  });
}
