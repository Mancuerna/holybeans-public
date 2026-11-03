/// A brew that could be the favourite of its coffee and method, e.g. one
/// marked in BeanConqueror.
typedef FavoriteCandidate = ({
  String id,
  String coffeeId,
  String methodId,

  /// BeanConqueror's "best brew", stronger than its favourite heart.
  bool best,
  double? rating,
  int brewedAtMs,
});

/// One favourite per coffee and method, since a new brew starts from it:
/// the best brew first, then the best rated, then the latest.
Set<String> pickFavorites(Iterable<FavoriteCandidate> candidates) {
  final chosen = <(String, String), FavoriteCandidate>{};
  for (final candidate in candidates) {
    final key = (candidate.coffeeId, candidate.methodId);
    final current = chosen[key];
    if (current == null || _beats(candidate, current)) chosen[key] = candidate;
  }
  return {for (final candidate in chosen.values) candidate.id};
}

bool _beats(FavoriteCandidate a, FavoriteCandidate b) {
  if (a.best != b.best) return a.best;
  final ratingA = a.rating ?? -1;
  final ratingB = b.rating ?? -1;
  if (ratingA != ratingB) return ratingA > ratingB;
  return a.brewedAtMs > b.brewedAtMs;
}
