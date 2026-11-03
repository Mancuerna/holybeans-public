import 'package:holybeans/domain/freshness.dart';

typedef FreshnessCoffee = ({
  String id,
  String roaster,
  String? roastLevel,
  int? restDays,
});
typedef FreshnessLot = ({
  String id,
  String? roastDate,
  String? openedDate,
  int? frozenPauseDays,
});
typedef FreshnessBrew = ({
  String coffeeId,
  String? lotId,
  double? rating,
  int brewedAtMs,
  BrewStyle style,
});

/// Where a coffee stands in its freshness windows for both brew styles.
class CoffeeFreshness {
  const CoffeeFreshness({
    required this.day,
    required this.pausedDays,
    required this.restDays,
    required this.windows,
    required this.sweetSpots,
    this.openedDays,
    this.ratedDays = const [],
  });

  /// Effective days after roasting (frozen time not counted).
  final int day;
  final int pausedDays;
  final int? restDays;
  final Map<BrewStyle, FreshnessWindow> windows;
  final Map<BrewStyle, SweetSpot> sweetSpots;

  /// Days since the bag was opened, while it counts towards aging.
  final int? openedDays;

  /// This coffee's rated brews by effective day after roasting.
  final List<RatedDay> ratedDays;

  FreshnessPhase phase(BrewStyle style) => windows[style]!.phaseAt(day);
}

/// A rated brew of the coffee on the freshness chart.
typedef RatedDay = ({int day, double rating, BrewStyle style});

/// Freshness for [coffee] from its newest roast date among [lots] (its
/// active lots), or null without a roast date. [frozenOnlyAge] replaces the
/// age while all remaining coffee is frozen, since freezing stops the clock.
CoffeeFreshness? coffeeFreshnessFacts({
  required FreshnessCoffee coffee,
  required List<FreshnessLot> lots,
  required List<FreshnessCoffee> coffees,
  required List<FreshnessBrew> brews,
  required List<FreshnessLot> allLots,
  int? frozenOnlyAge,
  DateTime? now,
}) {
  final ratedDays = <RatedDay>[];
  FreshnessLot? newest;
  DateTime? roastDate;
  for (final lot in lots) {
    final date = DateTime.tryParse(lot.roastDate ?? '');
    if (date != null && (roastDate == null || date.isAfter(roastDate))) {
      roastDate = date;
      newest = lot;
    }
  }
  if (roastDate == null || newest == null) return null;
  final pause = newest.frozenPauseDays ?? 0;
  final today = now ?? DateTime.now();
  final openedDate = frozenOnlyAge == null
      ? DateTime.tryParse(newest.openedDate ?? '')
      : null;
  final age =
      frozenOnlyAge ??
      effectiveRoastAge(
        roastDate,
        today,
        frozenPauseDays: pause,
        openedDate: openedDate,
      );
  if (age == null) return null;
  final windows = {
    for (final style in BrewStyle.values)
      style: freshnessWindow(
        roastLevel: coffee.roastLevel,
        style: style,
        restDays: coffee.restDays,
      ),
  };
  return CoffeeFreshness(
    day: age,
    pausedDays: frozenOnlyAge == null ? pause : 0,
    restDays: coffee.restDays,
    openedDays: openedDate == null
        ? null
        : DateTime.utc(today.year, today.month, today.day)
              .difference(
                DateTime.utc(openedDate.year, openedDate.month, openedDate.day),
              )
              .inDays
              .clamp(0, 100000),
    windows: windows,
    sweetSpots: _sweetSpots(
      coffee: coffee,
      coffees: coffees,
      brews: brews,
      allLots: allLots,
      ratedDays: ratedDays,
    ),
    ratedDays: ratedDays,
  );
}

Map<BrewStyle, SweetSpot> _sweetSpots({
  required FreshnessCoffee coffee,
  required List<FreshnessCoffee> coffees,
  required List<FreshnessBrew> brews,
  required List<FreshnessLot> allLots,
  required List<RatedDay> ratedDays,
}) {
  final coffeeById = {for (final row in coffees) row.id: row};
  final lotById = {for (final lot in allLots) lot.id: lot};
  final roaster = coffee.roaster.trim().toLowerCase();
  final samples = {
    for (final style in BrewStyle.values) style: <RatedBrewSample>[],
  };
  for (final brew in brews) {
    final rating = brew.rating;
    final other = coffeeById[brew.coffeeId];
    final lot = lotById[brew.lotId];
    final roastDate = DateTime.tryParse(lot?.roastDate ?? '');
    if (rating == null || other == null || roastDate == null) continue;
    final day = effectiveRoastAge(
      roastDate,
      DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs),
      openedDate: DateTime.tryParse(lot?.openedDate ?? ''),
    );
    if (day == null) continue;
    final weight = sweetSpotWeight(
      sameCoffee: other.id == coffee.id,
      sameRoastLevel:
          coffee.roastLevel != null && other.roastLevel == coffee.roastLevel,
      sameRoaster:
          roaster.isNotEmpty && other.roaster.trim().toLowerCase() == roaster,
    );
    final style = brew.style;
    samples[style]!.add(
      RatedBrewSample(day: day, rating: rating, weight: weight),
    );
    if (other.id == coffee.id) {
      ratedDays.add((day: day, rating: rating, style: style));
    }
  }
  return {
    for (final entry in samples.entries) entry.key: ?findSweetSpot(entry.value),
  };
}
