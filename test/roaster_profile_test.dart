import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/roaster_profile.dart';

RoasterCoffee coffee(
  String id, {
  String roaster = 'North Star',
  int? price,
  double? rating,
  bool archived = false,
}) => (
  id: id,
  name: id,
  roaster: roaster,
  paidPriceCents: price,
  rating: rating,
  archived: archived,
);
List<RoasterProfile> profiles(
  List<RoasterCoffee> coffees, {
  List<RoasterPurchase> purchases = const [],
  List<RoasterBrew> brews = const [],
  List<RoasterOrigin> origins = const [],
}) => RoasterProfile.fromJournal(
  coffees: coffees,
  purchases: purchases,
  brews: brews,
  origins: origins,
);

void main() {
  test('groups only case and spacing; preserves punctuation and accents', () {
    final result = profiles([
      coffee('z', archived: true),
      coffee('b'),
      coffee('a', roaster: '  NORTH   Star '),
      coffee('c', roaster: 'North-Star'),
      coffee('d', roaster: 'Nórth Star'),
      coffee('e', roaster: '  '),
    ]);
    expect(result.length, 3);
    final north = result.first;
    expect(north.name, 'North Star');
    expect(north.coffees.map((c) => c.id), ['a', 'b', 'z']);
    expect(
      profiles(result.expand((p) => p.coffees).toList().reversed.toList())
          .first
          .name,
      north.name,
    );
  });
  test(
    'sums purchase amounts and prices once per coffee, including archived',
    () {
      final p = profiles(
        [
          coffee('a', price: 1500, archived: true),
          coffee('b', price: 0),
          coffee('c'),
          coffee('d', price: 2500),
        ],
        purchases: [
          (coffeeId: 'a', grams: 250, purchaseDate: null),
          (coffeeId: 'a', grams: 500, purchaseDate: null),
          (coffeeId: 'b', grams: 0, purchaseDate: null),
          (coffeeId: 'c', grams: 100, purchaseDate: null),
          (coffeeId: 'c', grams: null, purchaseDate: null),
        ],
      ).single;
      expect(p.spentCents, 4000);
      expect(p.pricedCoffees, 3);
      expect(p.purchasedGrams, 750);
      expect(p.weighedCoffees, 2);
      expect(p.lastPurchase, isNull);
      expect(p.datedCoffees, 0);
    },
  );
  test(
    'unknown and invalid values stay out of averages and totals; zero counts',
    () {
      final p = profiles(
        [
          coffee('a', rating: 0, price: -1),
          coffee('b', rating: 8),
          coffee('c', rating: double.nan),
        ],
        purchases: [
          (coffeeId: 'a', grams: double.nan, purchaseDate: null),
          (coffeeId: 'b', grams: -1, purchaseDate: null),
        ],
        brews: [
          (coffeeId: 'a', rating: 0),
          (coffeeId: 'a', rating: 10),
          (coffeeId: 'b', rating: null),
          (coffeeId: 'b', rating: 11),
          (coffeeId: 'unknown', rating: 5),
        ],
      ).single;
      expect(p.coffeeRating, 4);
      expect(p.coffeeRatingCount, 2);
      expect(p.brewRating, 5);
      expect(p.brewRatingCount, 2);
      expect(p.brewCount, 4);
      expect(p.brewsByCoffee, {'a': 2, 'b': 2});
      expect(p.weighedCoffees, 0);
      expect(p.pricedCoffees, 0);
    },
  );
  test(
    'last purchase uses only valid explicit dates, excluding zero quantity',
    () {
      final p = profiles(
        [coffee('a'), coffee('b')],
        purchases: [
          (coffeeId: 'a', grams: 250, purchaseDate: '2025-02-28'),
          (coffeeId: 'a', grams: 250, purchaseDate: '2025-02-30'),
          (coffeeId: 'b', grams: null, purchaseDate: '2026-01-15'),
          (coffeeId: 'b', grams: 0, purchaseDate: '2026-12-31'),
          (coffeeId: 'b', grams: 250, purchaseDate: 'not a date'),
        ],
      ).single;
      expect(p.lastPurchase, DateTime(2026, 1, 15));
      expect(p.datedCoffees, 2);
    },
  );
  test(
    'origins count brewed coffees only and merge country aliases in blends',
    () {
      final p = profiles(
        [coffee('a'), coffee('b'), coffee('c')],
        brews: [(coffeeId: 'a', rating: null), (coffeeId: 'b', rating: null)],
        origins: [
          (coffeeId: 'a', country: 'Etiopía'),
          (coffeeId: 'a', country: 'Ethiopia'),
          (coffeeId: 'a', country: 'Colombia'),
          (coffeeId: 'b', country: ' '),
          (coffeeId: 'c', country: 'Brazil'),
        ],
      ).single;
      expect(p.countries.keys, unorderedEquals(['ET', 'CO']));
      expect(p.coffeesWithOrigin, 1);
    },
  );
  test('a blend written in one country field counts each country', () {
    final p = profiles(
      [coffee('a')],
      brews: [(coffeeId: 'a', rating: null)],
      origins: [(coffeeId: 'a', country: 'Colombia; Brazil')],
    ).single;
    expect(p.countries.keys, unorderedEquals(['CO', 'BR']));
    expect(p.coffeesWithOrigin, 1);
  });
}
