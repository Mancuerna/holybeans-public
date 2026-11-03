import 'package:holybeans/domain/freshness.dart';

/// What Home needs to know of a coffee at hand to place it.
typedef HomeCoffeeFacts = ({
  String id,
  FreshnessPhase? phase,

  /// Days left in [phase], counting today; null once stale.
  int? daysLeft,
  int? lastBrewedAtMs,
  int createdAtMs,
});

/// The coffees at hand as Home shows them: those to use soon and those
/// ready, a few of each; while there is room, those resting that were
/// already brewed and those without a roast date; and how many others are
/// still resting.
class HomeCoffees {
  const HomeCoffees({
    required this.spendSoon,
    required this.ready,
    required this.resting,
    required this.undated,
    required this.spendSoonCount,
    required this.readyCount,
    required this.restingCount,
    required this.waitingCount,
    required this.undatedCount,
    this.firstReadyInDays,
  });

  /// Aging or stale, the most pressing first.
  final List<String> spendSoon;

  /// In their prime or good, the most recently brewed first.
  final List<String> ready;

  /// All in each group, shown or not.
  final int spendSoonCount;
  final int readyCount;

  /// Still degassing but already brewed, the most recently brewed first,
  /// so a coffee in use can be repeated however fresh it is.
  final List<String> resting;

  /// All still degassing, and of those not in [resting], how many there
  /// are and in how many days the first is ready.
  final int restingCount;
  final int waitingCount;
  final int? firstReadyInDays;

  /// Without a roast date, so without a freshness phase: those shown, the
  /// most recently brewed first, and how many there are.
  final List<String> undated;
  final int undatedCount;

  bool get isEmpty =>
      spendSoonCount + readyCount + restingCount + undatedCount == 0;
}

/// Places [coffees] in Home's groups, keeping at most [perGroup] in each
/// and [shown] in all so Home stays short. Coffees without a roast date
/// take the room the others leave, so a journal without dates still offers
/// coffees to repeat.
HomeCoffees homeCoffees(
  List<HomeCoffeeFacts> coffees, {
  int perGroup = 3,
  int shown = 6,
}) {
  // Most recently brewed first; never brewed after, newest first.
  int byUse(HomeCoffeeFacts a, HomeCoffeeFacts b) {
    final last = (b.lastBrewedAtMs ?? -1).compareTo(a.lastBrewedAtMs ?? -1);
    return last != 0 ? last : b.createdAtMs.compareTo(a.createdAtMs);
  }

  // Stale before aging, then the fewest days left; use breaks ties.
  int byUrgency(HomeCoffeeFacts a, HomeCoffeeFacts b) {
    final left = (a.daysLeft ?? -1).compareTo(b.daysLeft ?? -1);
    return left != 0 ? left : byUse(a, b);
  }

  final spendSoon = [
    for (final coffee in coffees)
      if (coffee.phase == FreshnessPhase.aging ||
          coffee.phase == FreshnessPhase.stale)
        coffee,
  ]..sort(byUrgency);
  final ready = [
    for (final coffee in coffees)
      if (coffee.phase == FreshnessPhase.prime ||
          coffee.phase == FreshnessPhase.good)
        coffee,
  ]..sort(byUse);
  final resting = [
    for (final coffee in coffees)
      if (coffee.phase == FreshnessPhase.degassing) coffee,
  ];
  final brewedResting = [
    for (final coffee in resting)
      if (coffee.lastBrewedAtMs != null) coffee,
  ]..sort(byUse);
  final undated = [
    for (final coffee in coffees)
      if (coffee.phase == null) coffee,
  ]..sort(byUse);
  var room =
      shown - spendSoon.take(perGroup).length - ready.take(perGroup).length;
  final restingShown = brewedResting.take(room.clamp(0, perGroup)).toList();
  room -= restingShown.length;
  final waiting = [
    for (final coffee in resting)
      if (!restingShown.contains(coffee)) coffee,
  ];
  final waits = [for (final coffee in waiting) ?coffee.daysLeft];
  return HomeCoffees(
    spendSoon: [for (final coffee in spendSoon.take(perGroup)) coffee.id],
    ready: [for (final coffee in ready.take(perGroup)) coffee.id],
    undated: [
      for (final coffee in undated.take(room.clamp(0, perGroup))) coffee.id,
    ],
    spendSoonCount: spendSoon.length,
    readyCount: ready.length,
    resting: [for (final coffee in restingShown) coffee.id],
    restingCount: resting.length,
    waitingCount: waiting.length,
    firstReadyInDays: waits.isEmpty
        ? null
        : waits.reduce((a, b) => a < b ? a : b),
    undatedCount: undated.length,
  );
}

/// The brew Repeat starts from for a coffee: its favourite recipe, the
/// newest if it has one per method, or else its newest brew. [brews] are
/// the coffee's own, in any order.
T? repeatSeed<T>(
  List<T> brews, {
  required bool Function(T brew) isFavorite,
  required int Function(T brew) brewedAtMs,
}) {
  T? newest(Iterable<T> candidates) => candidates.fold<T?>(
    null,
    (best, brew) =>
        best == null || brewedAtMs(brew) > brewedAtMs(best) ? brew : best,
  );
  return newest(brews.where(isFavorite)) ?? newest(brews);
}
