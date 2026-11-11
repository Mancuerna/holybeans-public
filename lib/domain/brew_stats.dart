import 'package:holybeans/domain/calendar_days.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_inputs.dart';

/// Period the statistics cover, counted in local days ending today.
enum StatsRange {
  week(7),
  month(30),
  quarter(90),
  year(365),
  all(null);

  const StatsRange(this.days);

  final int? days;
}

/// Local calendar day of [time], as a UTC midnight so days compare exactly.
DateTime statsDay(DateTime time) => calendarDay(time);

/// Purchase cost in euros per kilogram, or null when either amount is
/// unknown or the purchased weight is not positive.
double? pricePerKgFor({
  required int? paidPriceCents,
  required double? initialGrams,
}) {
  if (paidPriceCents == null ||
      paidPriceCents < 0 ||
      initialGrams == null ||
      !initialGrams.isFinite ||
      initialGrams <= 0) {
    return null;
  }
  return paidPriceCents * 10 / initialGrams;
}

/// Price per kilo of each coffee with a known price and purchased weight:
/// what was paid over the grams bought across all its lots, archived ones
/// included, so older brews keep their cost.
Map<String, double> pricePerKgByCoffee(
  List<StatsCoffee> coffees,
  List<StatsLot> lots,
) {
  final bought = <String, double>{};
  final unknown = <String>{};
  for (final lot in lots) {
    final grams = lot.initialGrams;
    if (grams == null) {
      unknown.add(lot.coffeeId);
    } else {
      bought[lot.coffeeId] = (bought[lot.coffeeId] ?? 0) + grams;
    }
  }
  return {
    for (final coffee in coffees)
      if (coffee.paidPriceCents case final cents?
          when cents >= 0 &&
              !unknown.contains(coffee.id) &&
              (bought[coffee.id] ?? 0) > 0)
        coffee.id: cents * 10 / bought[coffee.id]!,
  };
}

/// Cost of [dose] grams of [coffeeId], or null without a dose or price.
double? brewCost(
  String coffeeId,
  double? dose,
  Map<String, double> pricePerKg,
) {
  final price = pricePerKg[coffeeId];
  return dose == null || price == null ? null : dose * price / 1000;
}

/// Brew counts per local day.
Map<DateTime, int> brewsPerDay(Iterable<int> brewedAtTimes) {
  final counts = <DateTime, int>{};
  for (final time in brewedAtTimes) {
    final day = statsDay(DateTime.fromMillisecondsSinceEpoch(time));
    counts.update(day, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Consecutive days with a brew ending today, or yesterday when today has
/// none yet, so a streak doesn't break before the morning coffee.
int currentStreak(Map<DateTime, int> counts, DateTime today) {
  var day = statsDay(today);
  if (!counts.containsKey(day)) day = day.subtract(const Duration(days: 1));
  var streak = 0;
  while (counts.containsKey(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

int longestStreak(Map<DateTime, int> counts) {
  final days = counts.keys.toList()..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && day.difference(previous).inDays == 1
        ? run + 1
        : 1;
    if (run > longest) longest = run;
    previous = day;
  }
  return longest;
}

/// A label with how many brews it covers and, when rated, their average.
class RankedItem {
  const RankedItem(this.label, this.count, {this.averageRating, this.flag});

  final String label;
  final int count;
  final double? averageRating;
  final String? flag;
}

/// Brews and average rating in one extraction compass cell.
class CompassCellStats {
  const CompassCellStats(this.count, this.averageRating);

  final int count;
  final double? averageRating;
}

class BrewStats {
  BrewStats._({
    required this.brews,
    required this.days,
    required this.groundGrams,
    required this.doseCount,
    required this.ratedCount,
    required this.averageRating,
    required this.compass,
    required this.methods,
    required this.origins,
    required this.roasters,
    required this.processes,
    required this.varieties,
    required this.beansTried,
    required this.roastersTried,
    required this.originsTried,
    required this.topRatedBeans,
    required this.ratingByStyle,
    required this.coffeeCost,
    required this.costedCount,
  });

  /// Statistics for the brews in [range], ending on [now]'s day. Archived
  /// beans and brews count too: they are still coffee you made.
  factory BrewStats.compute({
    required List<StatsBrew> brews,
    required List<StatsCoffee> coffees,
    required List<StatsComponent> components,
    required StatsRange range,
    required DateTime now,
    required String languageCode,
    Map<String, double> pricePerKg = const {},
  }) {
    final today = statsDay(now);
    final rangeDays = range.days;
    final start = rangeDays == null
        ? null
        : today.subtract(Duration(days: rangeDays - 1));
    final inRange = [
      for (final brew in brews)
        if (start == null ||
            !statsDay(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs))
                .isBefore(start))
          brew,
    ];
    final firstDay = brews.isEmpty
        ? null
        : brews
              .map(
                (brew) => statsDay(
                  DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs),
                ),
              )
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final observedStart = firstDay == null
        ? null
        : start != null && start.isAfter(firstDay)
        ? start
        : firstDay;
    final days = observedStart == null || observedStart.isAfter(today)
        ? 0
        : today.difference(observedStart).inDays + 1;

    final doses = [for (final brew in inRange) ?brew.doseGrams];
    final ratings = [for (final brew in inRange) ?brew.rating];

    final compassBrews = <(int, int), List<double?>>{};
    for (final brew in inRange) {
      final balance = brew.tasteBalance;
      final strength = brew.tasteStrength;
      if (balance == null || strength == null) continue;
      compassBrews.putIfAbsent((balance, strength), () => []).add(brew.rating);
    }

    final coffeeById = {for (final coffee in coffees) coffee.id: coffee};
    final countriesByCoffee = <String, Map<String, (String, String?)>>{};
    // Process and variety of each coffee, by lower-cased name.
    final processesByCoffee = <String, Map<String, String>>{};
    final varietiesByCoffee = <String, Map<String, String>>{};
    for (final component in components) {
      for (final (value, into) in [
        (component.process, processesByCoffee),
        (component.variety, varietiesByCoffee),
      ]) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) continue;
        into.putIfAbsent(component.coffeeId, () => {})[text.toLowerCase()] =
            text;
      }
    }
    for (final component in components) {
      final country = component.country?.trim();
      if (country == null || country.isEmpty) continue;
      final known = coffeeCountryFor(country);
      final key = known?.code ?? foldCountryName(country);
      countriesByCoffee.putIfAbsent(component.coffeeId, () => {})[key] = (
        known?.nameFor(languageCode) ?? country,
        known?.flag,
      );
    }

    final methodCounts = <String, _Tally>{};
    final originCounts = <String, _Tally>{};
    final roasterCounts = <String, _Tally>{};
    final beanCounts = <String, _Tally>{};
    final processCounts = <String, _Tally>{};
    final varietyCounts = <String, _Tally>{};
    final styleCounts = <BrewStyle, _Tally>{};
    for (final brew in inRange) {
      methodCounts
          .putIfAbsent(brew.methodName, () => _Tally(brew.methodName))
          .add(brew.rating);
      final coffee = coffeeById[brew.coffeeId];
      if (coffee != null) {
        final roaster = coffee.roaster.trim();
        if (roaster.isNotEmpty) {
          roasterCounts
              .putIfAbsent(roaster.toLowerCase(), () => _Tally(roaster))
              .add(brew.rating);
        }
        beanCounts
            .putIfAbsent(coffee.id, () => _Tally(coffee.name))
            .add(brew.rating);
      }
      for (final MapEntry(:key, value: (name, flag))
          in (countriesByCoffee[brew.coffeeId] ?? const {}).entries) {
        originCounts
            .putIfAbsent(key, () => _Tally(name, flag: flag))
            .add(brew.rating);
      }
      for (final (byCoffee, counts) in [
        (processesByCoffee, processCounts),
        (varietiesByCoffee, varietyCounts),
      ]) {
        for (final MapEntry(:key, value: name)
            in (byCoffee[brew.coffeeId] ?? const {}).entries) {
          counts.putIfAbsent(key, () => _Tally(name)).add(brew.rating);
        }
      }
      if (brew.rating != null) {
        styleCounts.putIfAbsent(brew.style, () => _Tally('')).add(brew.rating);
      }
    }

    List<RankedItem> top(Map<String, _Tally> tallies) {
      final items = tallies.values.toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      return [for (final tally in items.take(5)) tally.item];
    }

    final topRated =
        beanCounts.values.where((tally) => tally.ratings.length >= 2).toList()
          ..sort((a, b) {
            final byRating = b.average!.compareTo(a.average!);
            return byRating != 0 ? byRating : b.count.compareTo(a.count);
          });

    final costs = [
      for (final brew in inRange)
        ?brewCost(brew.coffeeId, brew.doseGrams, pricePerKg),
    ];

    return BrewStats._(
      coffeeCost: costs.fold(0, (sum, cost) => sum + cost),
      costedCount: costs.length,
      brews: inRange,
      days: days,
      groundGrams: doses.fold(0, (sum, dose) => sum + dose),
      doseCount: doses.length,
      ratedCount: ratings.length,
      averageRating: ratings.isEmpty
          ? null
          : ratings.reduce((a, b) => a + b) / ratings.length,
      compass: {
        for (final MapEntry(:key, :value) in compassBrews.entries)
          key: CompassCellStats(value.length, meanRating(value)),
      },
      methods: top(methodCounts),
      origins: top(originCounts),
      roasters: top(roasterCounts),
      processes: top(processCounts),
      varieties: top(varietyCounts),
      beansTried: beanCounts.length,
      roastersTried: roasterCounts.length,
      originsTried: originCounts.length,
      topRatedBeans: [for (final tally in topRated.take(5)) tally.item],
      ratingByStyle: {
        for (final MapEntry(:key, :value) in styleCounts.entries)
          key: value.item,
      },
    );
  }

  /// Brews within the range.
  final List<StatsBrew> brews;

  /// Days since the later of the range start and the journal’s first brew.
  final int days;
  final double groundGrams;
  final int doseCount;
  final int ratedCount;
  final double? averageRating;

  /// Extraction compass cells keyed by (balance, strength).
  final Map<(int, int), CompassCellStats> compass;
  final List<RankedItem> methods;
  final List<RankedItem> origins;
  final List<RankedItem> roasters;
  final List<RankedItem> processes;
  final List<RankedItem> varieties;

  /// Different coffees, roasters and origin countries brewed in the range.
  final int beansTried;
  final int roastersTried;
  final int originsTried;

  /// Beans with at least two rated brews, best average first.
  final List<RankedItem> topRatedBeans;
  final Map<BrewStyle, RankedItem> ratingByStyle;

  /// Value of the coffee used in the brews with a dose and a known price.
  final double coffeeCost;
  final int costedCount;

  double? get costPerCup => costedCount == 0 ? null : coffeeCost / costedCount;

  int get count => brews.length;
  double? get averageDose => doseCount == 0 ? null : groundGrams / doseCount;
  double? get brewsPerDay => days == 0 ? null : count / days;
}

/// The mean of the ratings given, ignoring missing ones; null without any.
double? meanRating(Iterable<double?> values) {
  final rated = values.whereType<double>().toList();
  return rated.isEmpty ? null : rated.reduce((a, b) => a + b) / rated.length;
}

class _Tally {
  _Tally(this.label, {this.flag});

  final String label;
  final String? flag;
  int count = 0;
  final ratings = <double>[];

  void add(double? rating) {
    count++;
    if (rating != null) ratings.add(rating);
  }

  double? get average => meanRating(ratings);

  RankedItem get item =>
      RankedItem(label, count, averageRating: average, flag: flag);
}
