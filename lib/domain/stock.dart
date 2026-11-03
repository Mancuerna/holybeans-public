import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/freshness.dart';

/// Dose used for [coffeeId]: the median of its last five recorded doses, or
/// [fallback] when it has none yet.
double typicalDose(String coffeeId, List<Brew> brews, {double fallback = 15}) {
  final recent =
      brews
          .where((brew) => brew.coffeeId == coffeeId && brew.doseGrams != null)
          .toList()
        ..sort((a, b) => b.brewedAtMs.compareTo(a.brewedAtMs));
  final doses = [for (final brew in recent.take(5)) brew.doseGrams!]..sort();
  if (doses.isEmpty) return fallback;
  final middle = doses.length ~/ 2;
  return doses.length.isOdd
      ? doses[middle]
      : (doses[middle - 1] + doses[middle]) / 2;
}

/// A coffee with fewer than two doses of unfrozen coffee left.
class LowStock {
  const LowStock({
    required this.coffee,
    required this.freshGrams,
    required this.frozenGrams,
    required this.dose,
  });

  final Coffee coffee;
  final double freshGrams;
  final double frozenGrams;
  final double dose;

  /// Whole doses left in the unfrozen coffee.
  int get doses => (freshGrams / dose).floor();
}

/// Active coffees about to run out, fewest doses first. Coffees with no
/// unfrozen coffee left are not included: they are either used up or kept
/// in the freezer on purpose.
List<LowStock> lowStock({
  required List<Coffee> coffees,
  required List<Brew> brews,
  required Map<String, double> freshGrams,
  required Map<String, double> frozenGrams,
}) {
  final low = <LowStock>[];
  for (final coffee in coffees) {
    if (coffee.archivedAtMs != null) continue;
    final fresh = freshGrams[coffee.id];
    if (fresh == null || fresh <= 0) continue;
    final dose = typicalDose(coffee.id, brews);
    if (fresh >= 2 * dose) continue;
    low.add(
      LowStock(
        coffee: coffee,
        freshGrams: fresh,
        frozenGrams: frozenGrams[coffee.id] ?? 0,
        dose: dose,
      ),
    );
  }
  return low..sort((a, b) => a.freshGrams.compareTo(b.freshGrams));
}

/// Whole days between roasting and freezing: while frozen the coffee does
/// not keep ageing, so this is its age for as long as it stays frozen.
/// Null without a roast date or when frozen before the recorded roast date.
int? frozenAtRoastAge(FrozenPortion portion, DateTime? roastDate) {
  if (roastDate == null) return null;
  final frozen = DateTime.tryParse(portion.frozenDate);
  if (frozen == null) return null;
  return daysSinceRoast(roastDate, frozen);
}

/// Visible unfrozen grams of a lot, or null when its stock is unknown.
double? unfrozenGrams(CoffeeLot lot) {
  final remaining = lot.remainingGrams;
  if (remaining == null) return null;
  final balance = remaining - (lot.overdrawGrams ?? 0);
  return balance < 0 ? 0 : balance;
}

/// Grams still frozen per coffee, across its active lots.
Map<String, double> frozenGramsByCoffee(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
) {
  final coffeeByLot = {
    for (final lot in lots)
      if (lot.archivedAtMs == null) lot.id: lot.coffeeId,
  };
  final result = <String, double>{};
  for (final portion in portions) {
    final coffeeId = coffeeByLot[portion.lotId];
    if (coffeeId == null || portion.remainingGrams <= 0) continue;
    result[coffeeId] = (result[coffeeId] ?? 0) + portion.remainingGrams;
  }
  return result;
}

Map<String, DateTime> oldestFrozenDatesByCoffee(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
) {
  final coffeeByLot = {
    for (final lot in lots)
      if (lot.archivedAtMs == null) lot.id: lot.coffeeId,
  };
  final result = <String, DateTime>{};
  for (final portion in portions) {
    final coffeeId = coffeeByLot[portion.lotId];
    if (coffeeId == null || portion.remainingGrams <= 0) continue;
    final date = DateTime.tryParse(portion.frozenDate);
    if (date == null) continue;
    final previous = result[coffeeId];
    if (previous == null || date.isBefore(previous)) result[coffeeId] = date;
  }
  return result;
}

/// Known unfrozen grams per coffee; coffees with unknown stock are absent.
Map<String, double> unfrozenGramsByCoffee(List<CoffeeLot> lots) {
  final result = <String, double>{};
  final unknown = <String>{};
  for (final lot in lots.where((lot) => lot.archivedAtMs == null)) {
    final grams = unfrozenGrams(lot);
    if (grams == null) {
      unknown.add(lot.coffeeId);
    } else {
      result[lot.coffeeId] = (result[lot.coffeeId] ?? 0) + grams;
    }
  }
  return result..removeWhere((coffeeId, _) => unknown.contains(coffeeId));
}

/// Days the oldest coffee still in the freezer has been frozen, or null
/// when nothing is frozen.
int? oldestFreezeDays(
  List<CoffeeLot> lots,
  List<FrozenPortion> portions,
  DateTime now,
) {
  final activeLots = {
    for (final lot in lots)
      if (lot.archivedAtMs == null) lot.id,
  };
  int? oldest;
  for (final portion in portions) {
    if (portion.remainingGrams <= 0 || !activeLots.contains(portion.lotId)) {
      continue;
    }
    final frozen = DateTime.tryParse(portion.frozenDate);
    if (frozen == null) continue;
    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(frozen.year, frozen.month, frozen.day)).inDays;
    if (days >= 0 && (oldest == null || days > oldest)) oldest = days;
  }
  return oldest;
}

/// Mean recorded dose for this coffee and method, including archived brews.
/// Older brews without a method ID are matched by the recorded method name.
double? meanMethodDose(Brew brew, List<Brew> history) {
  var total = 0.0;
  var count = 0;
  for (final previous in history) {
    if (previous.coffeeId != brew.coffeeId) continue;
    final sameMethod = previous.methodId != null && brew.methodId != null
        ? previous.methodId == brew.methodId
        : previous.methodName == brew.methodName;
    final dose = previous.doseGrams;
    if (!sameMethod || dose == null || !dose.isFinite || dose <= 0) continue;
    total += dose;
    count++;
  }
  return count == 0 || !total.isFinite ? null : total / count;
}

/// An offer to archive because less than one usual dose remains.
class StockArchiveSuggestion {
  const StockArchiveSuggestion(
    this.coffee,
    this.remainingGrams,
    this.meanDose,
    this.methodName,
  );

  final Coffee coffee;
  final double remainingGrams;
  final double meanDose;
  final String methodName;
}

/// Suggests archiving only with known stock, a recorded dose for the method
/// just used, counting both available coffee and remaining frozen portions.
StockArchiveSuggestion? stockArchiveSuggestion({
  required Coffee coffee,
  required Brew brew,
  required List<Brew> history,
  required List<CoffeeLot> lots,
  required List<FrozenPortion> portions,
}) {
  if (coffee.archivedAtMs != null || coffee.id != brew.coffeeId) return null;
  final available = unfrozenGramsByCoffee(lots)[coffee.id];
  if (available == null) return null;
  final frozen = frozenGramsByCoffee(lots, portions)[coffee.id] ?? 0;
  final dose = meanMethodDose(brew, history);
  final remaining = available + frozen;
  if (dose == null || remaining >= dose) {
    return null;
  }
  return StockArchiveSuggestion(coffee, remaining, dose, brew.methodName);
}

/// A coffee's stock across its active lots and their freezer portions, as
/// its card and details show it.
class CoffeeStock {
  CoffeeStock({
    required this.lots,
    required List<FrozenPortion> portions,
    this.adjustments = const [],
  }) : frozen = [
         for (final portion in portions)
           if (_belongs(lots, portion) && portion.remainingGrams > 0) portion,
       ],
       thawed = [
         for (final portion in portions)
           if (_belongs(lots, portion) && portion.remainingGrams <= 0) portion,
       ];

  static bool _belongs(List<CoffeeLot> lots, FrozenPortion portion) =>
      lots.any((lot) => lot.id == portion.lotId);

  final List<CoffeeLot> lots;
  final List<StockAdjustment> adjustments;

  /// Portions with coffee left, and used-up ones.
  final List<FrozenPortion> frozen;
  final List<FrozenPortion> thawed;

  /// Grams bought, when every lot records it.
  double? get initialGrams =>
      lots.isEmpty || lots.any((lot) => lot.initialGrams == null)
      ? null
      : lots.fold<double>(0, (sum, lot) => sum + lot.initialGrams!);

  /// Unfrozen grams minus any overdraw, which can be negative; null when a
  /// lot's stock is unknown.
  double? get signedRemainingGrams =>
      lots.isEmpty || lots.any((lot) => lot.remainingGrams == null)
      ? null
      : lots.fold<double>(
          0,
          (sum, lot) => sum + lot.remainingGrams! - (lot.overdrawGrams ?? 0),
        );

  /// Unfrozen grams left, never below zero.
  double? get remainingGrams => switch (signedRemainingGrams) {
    final grams? => grams < 0 ? 0 : grams,
    null => null,
  };

  double get frozenGrams =>
      frozen.fold<double>(0, (sum, portion) => sum + portion.remainingGrams);

  /// Whether all the coffee left is in the freezer: brewing it means
  /// thawing a portion first. False when the unfrozen stock is unknown.
  bool get onlyFrozen =>
      frozen.isNotEmpty &&
      switch (remainingGrams) {
        final grams? => grams < 0.05,
        null => false,
      };

  /// Portions with coffee left, the longest frozen first: the one to thaw
  /// next.
  List<FrozenPortion> get frozenOldestFirst => [...frozen]
    ..sort((a, b) {
      final byDate = a.frozenDate.compareTo(b.frozenDate);
      return byDate != 0 ? byDate : a.label.compareTo(b.label);
    });

  /// Grams brewed: bought minus what is left, fresh or frozen.
  double? get consumedGrams {
    final initial = initialGrams;
    final remaining = signedRemainingGrams;
    if (initial == null || remaining == null) return null;
    final active = adjustments.where(
      (r) => r.reversedAtMs == null && lots.any((lot) => lot.id == r.lotId),
    );
    if (active.any((r) => r.previousGrams == null)) return null;
    final delta = active.fold<double>(
      0,
      (sum, r) => sum + r.resultingGrams - r.previousGrams!,
    );
    return (initial - remaining - frozenGrams + delta).clamp(
      0,
      double.infinity,
    );
  }

  DateTime? roastDateOf(FrozenPortion portion) => DateTime.tryParse(
    lots.where((lot) => lot.id == portion.lotId).firstOrNull?.roastDate ?? '',
  );

  /// When all that is left is frozen, the oldest age a portion had when it
  /// was frozen: frozen coffee stops ageing. Null otherwise.
  int? get frozenOnlyAge {
    final remaining = signedRemainingGrams;
    if (remaining == null || remaining > 0) return null;
    int? oldest;
    for (final portion in frozen) {
      final age = frozenAtRoastAge(portion, roastDateOf(portion));
      if (age != null && (oldest == null || age > oldest)) oldest = age;
    }
    return oldest;
  }
}
