import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/coffee_year_costs.dart';
import 'package:holybeans/domain/coffee_year_inputs.dart';

class YearRank {
  const YearRank(this.id, this.name, this.count);
  final String id;
  final String name;
  final int count;
}

/// A calendar year in the device's local timezone, using preparation dates.
/// Archived/imported entries count; future entries and unknown values do not
/// become invented consumption, origins or ratings.
class CoffeeYear {
  CoffeeYear({
    required this.year,
    required DateTime now,
    required List<YearBrew> brews,
    required List<YearCoffee> coffees,
    required List<YearOrigin> components,
    required List<YearMethod> methods,
    List<YearPurchase> purchases = const [],
    Map<String, double> pricePerKg = const {},
  }) : asOf = now.toLocal() {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    entries =
        brews.where((brew) {
          final at = DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs);
          return !at.isBefore(start) && at.isBefore(end) && !at.isAfter(asOf);
        }).toList()..sort((a, b) {
          final order = a.brewedAtMs.compareTo(b.brewedAtMs);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
    final beans = {for (final coffee in coffees) coffee.id: coffee};
    final equipment = {for (final method in methods) method.id: method.name};
    final beanCounts = <String, int>{};
    final roasterCounts = <String, int>{};
    final roasterNames = <String, String>{};
    final methodCounts = <String, int>{};
    final methodNames = <String, String>{};
    final days = <DateTime>{};
    final monthBeans = List.generate(12, (_) => <String>{});
    final origins = <String, Set<String>>{};
    final originNames = <String, String>{};
    for (final component in components) {
      final text = component.country?.trim() ?? '';
      if (text.isEmpty) continue;
      final country = coffeeCountryFor(text);
      final id = country?.code ?? foldCountryName(text);
      (origins[component.coffeeId] ??= {}).add(id);
      originNames.putIfAbsent(id, () => country?.english ?? text);
    }
    final countryCounts = <String, int>{};
    for (final brew in entries) {
      final at = DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs);
      days.add(DateTime(at.year, at.month, at.day));
      monthlyBrews[at.month - 1]++;
      monthBeans[at.month - 1].add(brew.coffeeId);
      beanCounts.update(brew.coffeeId, (n) => n + 1, ifAbsent: () => 1);
      final roaster = beans[brew.coffeeId]?.roaster.trim() ?? '';
      if (roaster.isNotEmpty) {
        final key = roaster.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        roasterNames.putIfAbsent(key, () => roaster);
        roasterCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
      final name = equipment[brew.methodId] ?? brew.methodName.trim();
      if (name.isNotEmpty) {
        final key = brew.methodId ?? 'name:${name.toLowerCase()}';
        methodNames[key] = name;
        methodCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
      final dose = brew.doseGrams;
      if (dose != null && dose.isFinite && dose > 0) {
        doseGrams += dose;
        knownDoses++;
      }
      if (brew.rating case final rating?
          when rating.isFinite && rating >= 0 && rating <= 10) {
        rated.add(brew);
      }
    }
    for (final id in beanCounts.keys) {
      final countries = origins[id] ?? {};
      if (countries.isNotEmpty) coffeesWithOrigin++;
      for (final country in countries) {
        countryCounts.update(country, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    activeDays = days.length;
    coffeeCount = beanCounts.length;
    monthlyCoffees = monthBeans.map((set) => set.length).toList();
    coffeeRanks = _rank(beanCounts, {
      for (final id in beanCounts.keys) id: beans[id]?.name ?? '',
    });
    roasters = _rank(roasterCounts, roasterNames);
    methodRanks = _rank(methodCounts, methodNames);
    countries = _rank(countryCounts, originNames);
    rated.sort((a, b) {
      final rating = b.rating!.compareTo(a.rating!);
      return rating != 0 ? rating : a.brewedAtMs.compareTo(b.brewedAtMs);
    });
    coffeeNames = {for (final coffee in coffees) coffee.id: coffee.name};
    costs = CoffeeYearCosts(
      year: year,
      now: asOf,
      brews: entries,
      purchases: purchases,
      pricePerKg: pricePerKg,
    );
  }

  final int year;
  final DateTime asOf;
  late final CoffeeYearCosts costs;
  late final List<YearBrew> entries;
  late final Map<String, String> coffeeNames;
  late final List<YearRank> coffeeRanks;
  late final List<YearRank> roasters;
  late final List<YearRank> methodRanks;
  late final List<YearRank> countries;
  final List<YearBrew> rated = [];
  final List<int> monthlyBrews = List.filled(12, 0);
  late final List<int> monthlyCoffees;
  late final int activeDays;
  late final int coffeeCount;
  int knownDoses = 0;
  int coffeesWithOrigin = 0;
  double doseGrams = 0;

  bool get isPartial => year >= asOf.year;
  int get count => entries.length;
  int get topRatingTies => rated.isEmpty
      ? 0
      : rated.where((brew) => brew.rating == rated.first.rating).length;
  int get explorerMonth {
    var best = 0;
    for (var i = 1; i < 12; i++) {
      if (monthlyCoffees[i] > monthlyCoffees[best]) best = i;
    }
    return best + 1;
  }

  bool get explorerTie =>
      monthlyCoffees
          .where((count) => count == monthlyCoffees[explorerMonth - 1])
          .length >
      1;

  static List<YearRank> _rank(
    Map<String, int> counts,
    Map<String, String> names,
  ) =>
      [
        for (final entry in counts.entries)
          YearRank(entry.key, names[entry.key] ?? '', entry.value),
      ]..sort((a, b) {
        final count = b.count.compareTo(a.count);
        return count != 0 ? count : a.id.compareTo(b.id);
      });
}

List<int> coffeeYears(Iterable<int> timestamps, DateTime now) => {
  for (final timestamp in timestamps)
    if (timestamp <= now.millisecondsSinceEpoch)
      DateTime.fromMillisecondsSinceEpoch(timestamp).year,
}.toList()..sort((a, b) => b.compareTo(a));

/// The seasonal invitation runs from December 25 through January 31.
/// All recorded years remain accessible from statistics throughout the year.
int? seasonalCoffeeYear(Iterable<int> timestamps, DateTime now) {
  final local = now.toLocal();
  final year = local.month == 12 && local.day >= 25
      ? local.year
      : local.month == 1
      ? local.year - 1
      : null;
  return year != null && coffeeYears(timestamps, local).contains(year)
      ? year
      : null;
}
