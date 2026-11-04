import 'package:holybeans/data/database/app_database.dart';

typedef CoffeeBrewTotals = ({
  int count,
  int rated,
  double ratingSum,
  int lastMs,
});

/// Small, complete journal aggregates plus a bounded set of recipe previews.
/// Preview rows never contain notes or pour JSON; actions fetch the full row.
class BrewOverview {
  const BrewOverview({
    this.byCoffee = const {},
    this.previews = const [],
    this.seeds = const {},
    this.latestActive = const [],
    this.doses = const {},
    this.yearDates = const [],
    this.weekCount = 0,
    this.recentDates = const {},
    this.firstCreatedMs,
  });

  final Map<String, CoffeeBrewTotals> byCoffee;
  final List<Brew> previews;
  final Map<String, Brew> seeds;
  final List<Brew> latestActive;
  final Map<String, double> doses;
  final List<int> yearDates;
  final int weekCount;
  final Map<int, int> recentDates;

  /// Expire old entries even when no write has refreshed the SQL overview.
  int weekCountAt(DateTime now) {
    final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    return recentDates.entries
        .where((entry) => entry.key >= cutoff)
        .fold(0, (sum, entry) => sum + entry.value);
  }

  final int? firstCreatedMs;
  int get count => byCoffee.values.fold(0, (sum, item) => sum + item.count);
}
