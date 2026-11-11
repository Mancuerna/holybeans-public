import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/statistics.dart';
import 'package:holybeans/domain/stats_inputs.dart';

/// How long each bar of a chart over time lasts.
enum StatsPeriod { day, week, month }

/// Days for the week and month ranges, weeks for the quarter, months for a
/// year or all time: few enough bars to read on a phone.
StatsPeriod periodFor(StatsRange range) => switch (range) {
  StatsRange.week => StatsPeriod.day,
  StatsRange.month || StatsRange.quarter => StatsPeriod.week,
  StatsRange.year || StatsRange.all => StatsPeriod.month,
};

/// The start of the [period] that holds [day] (weeks start on Monday).
DateTime periodStart(DateTime day, StatsPeriod period) {
  final date = statsDay(day);
  return switch (period) {
    StatsPeriod.day => date,
    StatsPeriod.week => date.subtract(Duration(days: date.weekday - 1)),
    StatsPeriod.month => DateTime.utc(date.year, date.month),
  };
}

DateTime _next(DateTime start, StatsPeriod period) => switch (period) {
  StatsPeriod.day => start.add(const Duration(days: 1)),
  StatsPeriod.week => start.add(const Duration(days: 7)),
  StatsPeriod.month => DateTime.utc(start.year, start.month + 1),
};

/// One bar over time: the period it starts and what it adds up.
class PeriodTotal {
  const PeriodTotal(this.start, this.value);

  final DateTime start;
  final double value;
}

/// [values] (a local time and an amount) added up per [period], from the
/// period holding [from] to the one holding [now], empty periods included.
/// Without [from], it starts at the earliest value.
List<PeriodTotal> totalsPerPeriod(
  Iterable<(DateTime, double)> values,
  StatsPeriod period, {
  required DateTime now,
  DateTime? from,
}) {
  final sums = <DateTime, double>{};
  DateTime? earliest;
  for (final (time, value) in values) {
    final start = periodStart(time, period);
    sums.update(start, (sum) => sum + value, ifAbsent: () => value);
    if (earliest == null || start.isBefore(earliest)) earliest = start;
  }
  final first = from == null ? earliest : periodStart(from, period);
  if (first == null) return const [];
  final last = periodStart(now, period);
  return [
    for (var start = first; !start.isAfter(last); start = _next(start, period))
      PeriodTotal(start, sums[start] ?? 0),
  ];
}

/// The first day of [range] ending on [now], or null for all time.
DateTime? rangeStart(StatsRange range, DateTime now) => switch (range.days) {
  final days? => statsDay(now).subtract(Duration(days: days - 1)),
  null => null,
};

/// How many values fall in each bucket of [width], from the lowest bucket
/// with one to the highest; empty buckets in between are kept.
List<({int from, int count})> histogram(Iterable<int> values, int width) {
  final counts = <int, int>{};
  for (final value in values) {
    final from = value ~/ width * width;
    counts.update(from, (count) => count + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return const [];
  final low = counts.keys.reduce((a, b) => a < b ? a : b);
  final high = counts.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (var from = low; from <= high; from += width)
      (from: from, count: counts[from] ?? 0),
  ];
}

/// The average rating of a group of brews, and how many were rated.
class RatedGroup {
  const RatedGroup(this.count, this.averageRating);

  final int count;
  final double averageRating;
}

/// Average rating per brew temperature, in steps of [step] °C; only rated
/// brews with a temperature count.
Map<int, RatedGroup> ratingByTemperature(
  Iterable<StatsBrew> brews, {
  int step = 2,
}) {
  final groups = <int, List<double>>{};
  for (final brew in brews) {
    final (rating, celsius) = (brew.rating, brew.temperatureC);
    if (rating == null || celsius == null || !celsius.isFinite) continue;
    groups.putIfAbsent(celsius.floor() ~/ step * step, () => []).add(rating);
  }
  return {
    for (final key in groups.keys.toList()..sort())
      key: RatedGroup(groups[key]!.length, meanRating(groups[key]!)!),
  };
}

/// How the rating goes as a coffee is dialled in: the average rating of
/// the first, second… brew of each coffee, counted over all its brews
/// ([allBrews]), for the rated ones among [inRange]. Brews after the
/// [cap]th count with the [cap]th.
Map<int, RatedGroup> learningCurve(
  Iterable<StatsBrew> allBrews,
  Iterable<StatsBrew> inRange, {
  int cap = 8,
}) {
  final order = <String, int>{};
  final byCoffee = <String, List<StatsBrew>>{};
  for (final brew in allBrews) {
    byCoffee.putIfAbsent(brew.coffeeId, () => []).add(brew);
  }
  for (final brews in byCoffee.values) {
    brews.sort((a, b) {
      final byTime = a.brewedAtMs.compareTo(b.brewedAtMs);
      return byTime != 0 ? byTime : a.createdAtMs.compareTo(b.createdAtMs);
    });
    for (final (index, brew) in brews.indexed) {
      order[brew.id] = index + 1;
    }
  }
  final groups = <int, List<double>>{};
  for (final brew in inRange) {
    final (rating, number) = (brew.rating, order[brew.id]);
    if (rating == null || number == null) continue;
    groups.putIfAbsent(number < cap ? number : cap, () => []).add(rating);
  }
  return {
    for (final key in groups.keys.toList()..sort())
      key: RatedGroup(groups[key]!.length, meanRating(groups[key]!)!),
  };
}

/// What a coffee cost per cup and how it was rated over some brews.
class CoffeeValue {
  const CoffeeValue({
    required this.coffee,
    required this.brewCount,
    required this.costPerCup,
    required this.ratedCount,
    required this.averageRating,
  });

  final StatsCoffee coffee;
  final int brewCount;

  /// The average cost of the coffee in its brews with a dose; null without
  /// a price.
  final double? costPerCup;
  final int ratedCount;
  final double? averageRating;
}

/// Cost per cup and rating of each coffee brewed in [brews].
List<CoffeeValue> coffeeValues(
  Iterable<StatsBrew> brews,
  Iterable<StatsCoffee> coffees,
  Map<String, double> pricePerKg,
) {
  final byCoffee = <String, List<StatsBrew>>{};
  for (final brew in brews) {
    byCoffee.putIfAbsent(brew.coffeeId, () => []).add(brew);
  }
  return [
    for (final coffee in coffees)
      if (byCoffee[coffee.id] case final brews?)
        () {
          final costs = [
            for (final brew in brews)
              ?brewCost(brew.coffeeId, brew.doseGrams, pricePerKg),
          ];
          final ratings = [for (final brew in brews) ?brew.rating];
          return CoffeeValue(
            coffee: coffee,
            brewCount: brews.length,
            costPerCup: costs.isEmpty
                ? null
                : costs.reduce((a, b) => a + b) / costs.length,
            ratedCount: ratings.length,
            averageRating: meanRating(ratings),
          );
        }(),
  ];
}

/// The coffees that please most for what they cost: among those with a
/// price and rated at least the median of them, the cheapest per cup.
List<CoffeeValue> bestValue(Iterable<CoffeeValue> values, {int take = 5}) {
  final rated = [
    for (final value in values)
      if (value.costPerCup != null && value.averageRating != null) value,
  ];
  if (rated.isEmpty) return const [];
  final medianRating = median([
    for (final value in rated) value.averageRating!,
  ])!;
  final good =
      [
        for (final value in rated)
          if (value.averageRating! >= medianRating) value,
      ]..sort((a, b) {
        final byCost = a.costPerCup!.compareTo(b.costPerCup!);
        return byCost != 0
            ? byCost
            : b.averageRating!.compareTo(a.averageRating!);
      });
  return good.take(take).toList();
}

/// A bag bought: when, what it cost and what it weighed.
typedef Purchase = ({DateTime date, double price, double grams});

/// When [lot] was bought: its purchase date, else its roast date, else when
/// it was added.
DateTime purchaseDate(StatsLot lot) =>
    DateTime.tryParse(lot.purchaseDate ?? '') ??
    DateTime.tryParse(lot.roastDate ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(lot.createdAtMs);

/// The bags bought, priced from their coffee's price per kilo; only those
/// bought from [from] on, when given. Bags without a price or weight are
/// left out.
List<Purchase> purchases(
  Iterable<StatsLot> lots,
  Map<String, double> pricePerKg, {
  DateTime? from,
}) => [
  for (final lot in lots)
    if ((pricePerKg[lot.coffeeId], lot.initialGrams) case (
      final price?,
      final grams?,
    ))
      if (from == null || !statsDay(purchaseDate(lot)).isBefore(statsDay(from)))
        (date: purchaseDate(lot), price: price * grams / 1000, grams: grams),
];

/// A roaster's average price per kilo over the bags with a price.
class RoasterPrice {
  const RoasterPrice(this.roaster, this.pricePerKg, this.bags);

  final String roaster;
  final double pricePerKg;
  final int bags;
}

/// Average price per kilo of each roaster, weighted by the grams of each
/// bag, dearest first; only bags dated from [from] on, when given.
List<RoasterPrice> pricePerKgByRoaster(
  Iterable<StatsCoffee> coffees,
  Iterable<StatsLot> lots,
  Map<String, double> pricePerKg, {
  DateTime? from,
}) {
  final roasterOf = {for (final coffee in coffees) coffee.id: coffee.roaster};
  final paid = <String, double>{};
  final grams = <String, double>{};
  final bags = <String, int>{};
  final names = <String, String>{};
  for (final lot in lots) {
    final roaster = roasterOf[lot.coffeeId]?.trim() ?? '';
    final price = pricePerKg[lot.coffeeId];
    final weight = lot.initialGrams;
    if (roaster.isEmpty || price == null || weight == null || weight <= 0) {
      continue;
    }
    if (from != null && statsDay(purchaseDate(lot)).isBefore(statsDay(from))) {
      continue;
    }
    final key = roaster.toLowerCase();
    names.putIfAbsent(key, () => roaster);
    paid.update(
      key,
      (sum) => sum + price * weight,
      ifAbsent: () => price * weight,
    );
    grams.update(key, (sum) => sum + weight, ifAbsent: () => weight);
    bags.update(key, (count) => count + 1, ifAbsent: () => 1);
  }
  return [
    for (final key in paid.keys)
      RoasterPrice(names[key]!, paid[key]! / grams[key]!, bags[key]!),
  ]..sort((a, b) => b.pricePerKg.compareTo(a.pricePerKg));
}

/// The median days from roasting to the first brew of each coffee first
/// brewed in [inRange], from the bag that brew used; null without any.
double? medianDaysToFirstBrew(
  Iterable<StatsBrew> allBrews,
  Iterable<StatsBrew> inRange,
  Iterable<StatsLot> lots,
) {
  final roastOf = {
    for (final lot in lots) lot.id: ?DateTime.tryParse(lot.roastDate ?? ''),
  };
  final first = <String, StatsBrew>{};
  for (final brew in allBrews) {
    final known = first[brew.coffeeId];
    if (known == null || brew.brewedAtMs < known.brewedAtMs) {
      first[brew.coffeeId] = brew;
    }
  }
  final ids = {for (final brew in inRange) brew.id};
  final days = <int>[
    for (final brew in first.values)
      if (ids.contains(brew.id))
        if (roastOf[brew.lotId] case final roasted?)
          if (statsDay(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs))
                  .difference(statsDay(roasted))
                  .inDays
              case final age when age >= 0)
            age,
  ];
  return median(days);
}

/// Typical figures for one brewing style, as medians so a cold brew or a
/// timer left running does not drag them: ratio (water, or yield for
/// espresso, per gram of coffee) and time in seconds.
class StyleAverages {
  const StyleAverages({this.ratio, this.timeSeconds, this.times = const []});

  final double? ratio;
  final double? timeSeconds;

  /// Every brew time, for the distribution.
  final List<int> times;
}

/// [StyleAverages] for each style among [brews]: filter compares the water
/// with the dose; espresso, the yield.
Map<BrewStyle, StyleAverages> styleAverages(Iterable<StatsBrew> brews) {
  final ratios = <BrewStyle, List<double>>{};
  final times = <BrewStyle, List<int>>{};
  for (final brew in brews) {
    final style = brew.style;
    final dose = brew.doseGrams;
    final out = style == BrewStyle.espresso
        ? brew.beverageGrams
        : brew.waterGrams;
    if (dose != null && dose > 0 && out != null && out > 0) {
      ratios.putIfAbsent(style, () => []).add(out / dose);
    }
    if (brew.timeSeconds case final seconds? when seconds > 0) {
      times.putIfAbsent(style, () => []).add(seconds);
    }
  }
  return {
    for (final style in BrewStyle.values)
      if (ratios.containsKey(style) || times.containsKey(style))
        style: StyleAverages(
          ratio: median(ratios[style] ?? const []),
          timeSeconds: median(times[style] ?? const []),
          times: times[style] ?? const [],
        ),
  };
}
