import 'package:holybeans/domain/coffee_countries.dart';

typedef RoasterCoffee = ({
  String id,
  String name,
  String roaster,
  int? paidPriceCents,
  double? rating,
  bool archived,
});
typedef RoasterPurchase = ({
  String coffeeId,
  double? grams,
  String? purchaseDate,
});
typedef RoasterBrewTotals = ({int count, int rated, double ratingSum});

typedef RoasterBrew = ({String coffeeId, double? rating});
typedef RoasterCafeDrink = ({
  String id,
  String roaster,
  String cafe,
  String drinkType,
  String? origin,
  double? rating,
});

typedef RoasterOrigin = ({String coffeeId, String? country});

String roasterName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');
String roasterKey(String name) => roasterName(name).toLowerCase();

/// A read-only view of a roaster's recorded coffees, including archived ones.
/// Only case and whitespace are folded; spelling and punctuation stay distinct.
class RoasterProfile {
  RoasterProfile._({
    required this.key,
    this.cafeDrinks = const [],
    required List<RoasterCoffee> coffees,
    required List<RoasterPurchase> purchases,
    required List<RoasterBrew> brews,
    Map<String, RoasterBrewTotals>? brewTotals,
    required List<RoasterOrigin> origins,
  }) {
    final names = <String, int>{};
    for (final coffee in coffees) {
      final name = roasterName(coffee.roaster);
      names.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
    if (names.isEmpty) {
      for (final drink in cafeDrinks) {
        final name = roasterName(drink.roaster);
        names.update(name, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final spellings = names.keys.toList()
      ..sort((a, b) {
        final count = names[b]!.compareTo(names[a]!);
        return count == 0 ? a.compareTo(b) : count;
      });
    name = spellings.first;
    this.coffees = List.unmodifiable(
      coffees.toList()..sort((a, b) {
        if (a.archived != b.archived) return a.archived ? 1 : -1;
        final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return order == 0 ? a.id.compareTo(b.id) : order;
      }),
    );
    final ids = coffees.map((c) => c.id).toSet();
    final weights = <String, double>{};
    final unknownWeights = <String>{};
    final dated = <String>{};
    for (final purchase in purchases.where((p) => ids.contains(p.coffeeId))) {
      final grams = purchase.grams;
      if (grams == null || !grams.isFinite || grams < 0) {
        unknownWeights.add(purchase.coffeeId);
      } else {
        weights.update(
          purchase.coffeeId,
          (n) => n + grams,
          ifAbsent: () => grams,
        );
      }
      final date = _purchaseDate(purchase.purchaseDate);
      if (date != null && grams != 0) {
        dated.add(purchase.coffeeId);
        if (lastPurchase == null || date.isAfter(lastPurchase!)) {
          lastPurchase = date;
        }
      }
    }
    datedCoffees = dated.length;
    final coffeeRatings = <double>[];
    for (final coffee in coffees) {
      final weight = weights[coffee.id];
      if (weight != null &&
          weight.isFinite &&
          !unknownWeights.contains(coffee.id)) {
        purchasedGrams += weight;
        weighedCoffees++;
      }
      final cents = coffee.paidPriceCents;
      if (cents != null && cents >= 0) {
        spentCents += cents;
        pricedCoffees++;
      }
      if (_validRating(coffee.rating)) coffeeRatings.add(coffee.rating!);
    }
    coffeeRatingCount = coffeeRatings.length;
    coffeeRating = _average(coffeeRatings);
    final brewRatings = <double>[];
    for (final brew in brews.where((b) => ids.contains(b.coffeeId))) {
      brewCount++;
      brewsByCoffee.update(brew.coffeeId, (n) => n + 1, ifAbsent: () => 1);
      if (_validRating(brew.rating)) brewRatings.add(brew.rating!);
    }
    if (brewTotals == null) {
      brewRatingCount = brewRatings.length;
      brewRating = _average(brewRatings);
    } else {
      brewCount = 0;
      brewsByCoffee.clear();
      var rated = 0;
      var sum = 0.0;
      for (final id in ids) {
        final totals = brewTotals[id];
        if (totals == null) continue;
        brewCount += totals.count;
        if (totals.count > 0) brewsByCoffee[id] = totals.count;
        rated += totals.rated;
        sum += totals.ratingSum;
      }
      brewRatingCount = rated;
      brewRating = rated == 0 ? null : sum / rated;
    }
    final originCoffees = <String>{};
    final countries = <String, String>{};
    for (final origin in origins.where(
      (o) => brewsByCoffee.containsKey(o.coffeeId),
    )) {
      // A blend written in one field ("Colombia; Brazil") counts each.
      final names = (origin.country ?? '')
          .split(RegExp(r'\s*(?:;|/)\s*'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty);
      for (final text in names) {
        originCoffees.add(origin.coffeeId);
        final country = coffeeCountryFor(text);
        countries[country?.code ?? foldCountryName(text)] =
            country?.english ?? text;
      }
    }
    coffeesWithOrigin = originCoffees.length;
    this.countries = Map.unmodifiable(countries);
  }

  final String key;
  late final String name;
  late final List<RoasterCoffee> coffees;
  late final Map<String, String> countries;
  final brewsByCoffee = <String, int>{};
  int brewCount = 0;
  int spentCents = 0;
  int pricedCoffees = 0;
  double purchasedGrams = 0;
  int weighedCoffees = 0;
  late final int datedCoffees;
  DateTime? lastPurchase;
  late final int coffeeRatingCount;
  late final double? coffeeRating;
  late final int brewRatingCount;
  late final double? brewRating;
  late final int coffeesWithOrigin;

  final List<RoasterCafeDrink> cafeDrinks;
  double? get cafeRating => _average([
    for (final d in cafeDrinks)
      if (_validRating(d.rating)) d.rating!,
  ]);

  static bool _validRating(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 10;
  static double? _average(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
  static DateTime? _purchaseDate(String? text) {
    if (text == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return null;
    }
    final date = DateTime.tryParse(text);
    if (date == null ||
        date.month != int.parse(text.substring(5, 7)) ||
        date.day != int.parse(text.substring(8))) {
      return null;
    }
    return date;
  }

  static List<RoasterProfile> fromJournal({
    required List<RoasterCoffee> coffees,
    required List<RoasterPurchase> purchases,
    required List<RoasterBrew> brews,
    Map<String, RoasterBrewTotals>? brewTotals,
    required List<RoasterOrigin> origins,
    List<RoasterCafeDrink> cafeDrinks = const [],
  }) {
    final groups = <String, List<RoasterCoffee>>{};
    for (final coffee in coffees) {
      final key = roasterKey(coffee.roaster);
      if (key.isNotEmpty) (groups[key] ??= []).add(coffee);
    }
    for (final drink in cafeDrinks) {
      final key = roasterKey(drink.roaster);
      if (key.isNotEmpty) groups.putIfAbsent(key, () => []);
    }
    return [
      for (final entry in groups.entries)
        RoasterProfile._(
          key: entry.key,
          cafeDrinks: List.unmodifiable(
            cafeDrinks.where((d) => roasterKey(d.roaster) == entry.key),
          ),
          coffees: entry.value,
          purchases: purchases,
          brews: brews,
          brewTotals: brewTotals,
          origins: origins,
        ),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }
}
