import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stock.dart';

CoffeeLot lot(
  String id, {
  double? initial,
  double? remaining,
  double? overdraw,
  String? roast,
}) => CoffeeLot(
  id: id,
  coffeeId: 'c',
  initialGrams: initial,
  remainingGrams: remaining,
  overdrawGrams: overdraw,
  roastDate: roast,
  createdAtMs: 0,
  updatedAtMs: 0,
);

FrozenPortion portion(String id, String lotId, double grams, String frozen) =>
    FrozenPortion(
      id: id,
      lotId: lotId,
      label: id,
      initialGrams: 100,
      remainingGrams: grams,
      frozenDate: frozen,
      createdAtMs: 0,
      updatedAtMs: 0,
    );

void main() {
  test('stock sums lots, keeps overdraw apart and splits portions', () {
    final stock = CoffeeStock(
      lots: [
        lot('a', initial: 250, remaining: 40, overdraw: 10),
        lot('b', initial: 250, remaining: 100),
      ],
      portions: [
        portion('p1', 'a', 60, '2026-10-01'),
        portion('p2', 'b', 0, '2026-10-01'),
        portion('other', 'x', 80, '2026-10-01'),
      ],
    );
    expect(stock.initialGrams, 500);
    expect(stock.signedRemainingGrams, 130);
    expect(stock.remainingGrams, 130);
    expect(stock.frozenGrams, 60);
    expect(stock.consumedGrams, 310);
    expect(stock.frozen.map((p) => p.id), ['p1']);
    expect(stock.thawed.map((p) => p.id), ['p2']);
  });

  test('unknown stock stays unknown and overdraw floors at zero', () {
    expect(
      CoffeeStock(lots: [lot('a')], portions: const []).remainingGrams,
      isNull,
    );
    final overdrawn = CoffeeStock(
      lots: [lot('a', initial: 250, remaining: 0, overdraw: 30)],
      portions: const [],
    );
    expect(overdrawn.signedRemainingGrams, -30);
    expect(overdrawn.remainingGrams, 0);
    expect(overdrawn.consumedGrams, 280);
  });

  test('all frozen: the age is the oldest one at freezing', () {
    final stock = CoffeeStock(
      lots: [lot('a', remaining: 0, roast: '2026-09-01')],
      portions: [
        portion('p1', 'a', 50, '2026-09-11'),
        portion('p2', 'a', 50, '2026-09-21'),
      ],
    );
    expect(stock.frozenOnlyAge, 20);
    final fresh = CoffeeStock(
      lots: [lot('a', remaining: 20, roast: '2026-09-01')],
      portions: [portion('p1', 'a', 50, '2026-09-11')],
    );
    expect(fresh.frozenOnlyAge, isNull);
  });

  test('brewing only frozen coffee means thawing the oldest portion', () {
    final frozenOnly = CoffeeStock(
      lots: [lot('a', remaining: 0)],
      portions: [
        portion('newer', 'a', 40, '2026-09-20'),
        portion('older', 'a', 60, '2026-09-02'),
      ],
    );
    expect(frozenOnly.onlyFrozen, isTrue);
    expect(frozenOnly.frozenOldestFirst.map((p) => p.id), ['older', 'newer']);

    expect(
      CoffeeStock(
        lots: [lot('a', remaining: 18)],
        portions: [portion('p', 'a', 40, '2026-09-20')],
      ).onlyFrozen,
      isFalse,
      reason: 'there is coffee outside the freezer',
    );
    expect(
      CoffeeStock(
        lots: [lot('a')],
        portions: [portion('p', 'a', 40, '2026-09-20')],
      ).onlyFrozen,
      isFalse,
      reason: 'the stock outside the freezer is unknown',
    );
    expect(
      CoffeeStock(
        lots: [lot('a', remaining: 0)],
        portions: const [],
      ).onlyFrozen,
      isFalse,
    );
  });
}
