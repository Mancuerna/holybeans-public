import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/text_suggestions.dart';

typedef HistoryQuery = ({
  String text,
  bool archived,
  bool ascending,
  String? coffeeId,
  String? methodId,
  String? methodName,
  int? startMs,
  int? endMs,
  double? minimumRating,
});

typedef HistoryRequest = ({
  List<Brew> brews,
  List<Coffee> coffees,
  HistoryQuery query,
});

/// Indices keep the original immutable rows in the UI. Worker results need not
/// copy notes or deserialize a second journal to display matching cards.
List<int> selectHistory(HistoryRequest request) {
  final (:brews, :coffees, :query) = request;
  final coffeeById = {for (final coffee in coffees) coffee.id: coffee};
  final visible = <int>[];
  final matcher = FoldedTextMatcher(query.text);
  for (var i = 0; i < brews.length; i++) {
    final brew = brews[i];
    if (!query.archived && brew.archivedAtMs != null) continue;
    if (query.coffeeId != null && brew.coffeeId != query.coffeeId) continue;
    if (query.methodId != null) {
      if (brew.methodId != null) {
        if (brew.methodId != query.methodId) continue;
      } else if (query.methodName != brew.methodName) {
        continue;
      }
    } else if (query.methodName != null &&
        brew.methodName != query.methodName) {
      continue;
    }
    if (query.startMs != null && brew.brewedAtMs < query.startMs!) continue;
    if (query.endMs != null && brew.brewedAtMs >= query.endMs!) continue;
    if (query.minimumRating != null &&
        (brew.rating == null || brew.rating! < query.minimumRating!)) {
      continue;
    }
    if (query.text.isNotEmpty) {
      final coffee = coffeeById[brew.coffeeId];
      final prefix =
          '${coffee?.name ?? ''} ${coffee?.roaster ?? ''} '
          '${brew.methodName} ${brew.grinderName ?? ''}';
      // Preserve the original full-string fallback for phrases that cross
      // field boundaries. A metadata hit never needs to touch a long note.
      if (!matcher.matches(prefix) &&
          !matcher.matches('$prefix ${brew.notes ?? ''}')) {
        continue;
      }
    }
    visible.add(i);
  }
  visible.sort((first, second) {
    final a = brews[first];
    final b = brews[second];
    final byTime = a.brewedAtMs.compareTo(b.brewedAtMs);
    if (byTime != 0) return query.ascending ? byTime : -byTime;
    final byCreated = b.createdAtMs.compareTo(a.createdAtMs);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  });
  return visible;
}
