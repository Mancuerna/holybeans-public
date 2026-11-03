import 'package:holybeans/domain/coffee_year_inputs.dart';

typedef YearPurchase = ({
  String coffeeId,
  int atMs,
  double? euros,
  bool estimatedDate,
});
typedef YearCoffeePrice = ({String coffeeId, double eurosPerKg});
typedef YearCupCost = ({YearBrew brew, double euros});

/// Recorded purchase spending and estimated coffee-only preparation costs.
/// Prices are the journal's current weighted price per kilo, as in statistics.
class CoffeeYearCosts {
  CoffeeYearCosts({
    required int year,
    required DateTime now,
    required List<YearBrew> brews,
    required List<YearPurchase> purchases,
    required Map<String, double> pricePerKg,
  }) {
    bool inYear(int ms) {
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      return date.year == year && !date.isAfter(now);
    }

    final bought = <String>{};
    final costed = <String>{};
    final estimated = <String>{};
    for (final purchase in purchases.where((p) => inYear(p.atMs))) {
      bought.add(purchase.coffeeId);
      if (purchase.estimatedDate) estimated.add(purchase.coffeeId);
      final amount = purchase.euros;
      if (amount == null || !amount.isFinite || amount < 0) continue;
      costed.add(purchase.coffeeId);
      totalEuros += amount;
      final month = DateTime.fromMillisecondsSinceEpoch(purchase.atMs).month;
      monthlyEuros[month - 1] += amount;
    }
    purchasedCoffees = bought.length;
    costedCoffees = costed.length;
    estimatedDateCoffees = estimated.length;
    coffeePrices =
        [
          for (final id in costed)
            if (pricePerKg[id] case final price?
                when price.isFinite && price >= 0)
              (coffeeId: id, eurosPerKg: price),
        ]..sort((a, b) {
          final order = cents(a.eurosPerKg).compareTo(cents(b.eurosPerKg));
          return order == 0 ? a.coffeeId.compareTo(b.coffeeId) : order;
        });
    for (final brew in brews.where((b) => inYear(b.brewedAtMs))) {
      brewCount++;
      final dose = brew.doseGrams;
      final price = pricePerKg[brew.coffeeId];
      if (dose == null ||
          !dose.isFinite ||
          dose <= 0 ||
          price == null ||
          !price.isFinite ||
          price < 0) {
        continue;
      }
      final amount = dose * price / 1000;
      if (amount.isFinite) cups.add((brew: brew, euros: amount));
    }
    cups.sort((a, b) {
      final order = cents(a.euros).compareTo(cents(b.euros));
      if (order != 0) return order;
      final date = a.brew.brewedAtMs.compareTo(b.brew.brewedAtMs);
      return date == 0 ? a.brew.id.compareTo(b.brew.id) : date;
    });
  }

  double totalEuros = 0;
  final monthlyEuros = List<double>.filled(12, 0);
  late final int purchasedCoffees;
  late final int costedCoffees;
  late final int estimatedDateCoffees;
  late final List<YearCoffeePrice> coffeePrices;
  final List<YearCupCost> cups = [];
  int brewCount = 0;

  // Rank and acknowledge ties at the precision shown to the reader.
  static int cents(double euros) => (euros * 100).round();
  int coffeeTies(YearCoffeePrice price) => coffeePrices
      .where((p) => cents(p.eurosPerKg) == cents(price.eurosPerKg))
      .length;
  int cupTies(YearCupCost cup) =>
      cups.where((c) => cents(c.euros) == cents(cup.euros)).length;
}
