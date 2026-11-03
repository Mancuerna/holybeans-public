import 'package:holybeans/data/database/app_database.dart';

/// Saved recipe and its canonical tools; query results expose an unmodifiable list.
typedef BrewRecipeMemory = ({Brew brew, bool favorite, List<String> toolIds});

/// Independent references for the advice card and the most recent notes.
typedef BrewReferences = ({
  Brew? favorite,
  Brew? last,
  bool lastRated,
  Brew? newest,
});

/// The form only needs these reads, not the journal's write operations.
typedef LoadBrewMemory = Future<BrewRecipeMemory?> Function({
  required String? coffeeId,
  required String methodId,
});
typedef LoadBrewReferences = Future<BrewReferences> Function({
  required String coffeeId,
  required String methodId,
});
