part of '../journal_repository.dart';

/// Brews, their tasting and the stock they use.
extension BrewOperations on JournalRepository {
  Future<String> createBrew({
    required String coffeeId,
    required String methodName,
    String? lotId,
    String? methodId,
    String? grinderName,
    String? grinderId,
    String? waterProfileId,
    bool isPreGround = false,
    String? grindSetting,
    List<String>? methodToolIds,
    double? doseGrams,
    FrozenBrewSource? frozenSource,
    double? waterGrams,
    double? beverageGrams,
    int? timeSeconds,
    double? temperatureC,
    double? tdsPercent,
    double? brix,
    double? brixFactor,
    int? grindRpm,
    int? feederRpm,
    double? pressureBar,
    int? preinfusionSeconds,
    int? bloomSeconds,
    BrewPours? pours,
    int? firstDripSeconds,
    double? rating,
    String? notes,
    String? profileName,
    DateTime? brewedAt,
  }) => saveBrew(
    coffeeId: coffeeId,
    methodName: methodName,
    lotId: lotId,
    methodId: methodId,
    grinderName: grinderName,
    grinderId: grinderId,
    waterProfileId: waterProfileId,
    isPreGround: isPreGround,
    grindSetting: grindSetting,
    methodToolIds: methodToolIds,
    doseGrams: doseGrams,
    frozenSource: frozenSource,
    waterGrams: waterGrams,
    beverageGrams: beverageGrams,
    timeSeconds: timeSeconds,
    temperatureC: temperatureC,
    tdsPercent: tdsPercent,
    brix: brix,
    brixFactor: brixFactor,
    grindRpm: grindRpm,
    feederRpm: feederRpm,
    pressureBar: pressureBar,
    preinfusionSeconds: preinfusionSeconds,
    bloomSeconds: bloomSeconds,
    pours: pours,
    firstDripSeconds: firstDripSeconds,
    rating: rating,
    notes: notes,
    profileName: profileName,
    brewedAt: brewedAt,
  );

  /// Creates or updates a brew and adjusts the selected bag in one transaction.
  /// Unknown bag weights remain unknown; archiving preserves consumption.
  Future<String> saveBrew({
    String? id,
    required String coffeeId,
    required String methodName,
    String? lotId,
    String? methodId,
    String? grinderName,
    String? grinderId,
    String? waterProfileId,
    bool isPreGround = false,
    String? grindSetting,
    List<String>? methodToolIds,
    double? doseGrams,
    FrozenBrewSource? frozenSource,
    double? waterGrams,
    double? beverageGrams,
    int? timeSeconds,
    double? temperatureC,
    double? tdsPercent,
    double? brix,
    double? brixFactor,
    int? grindRpm,
    int? feederRpm,
    double? pressureBar,
    int? preinfusionSeconds,
    int? bloomSeconds,
    BrewPours? pours,
    int? firstDripSeconds,
    double? rating,
    String? notes,
    String? profileName,
    DateTime? brewedAt,
  }) async => (await saveBrewWithOutcome(
    BrewInput(
      coffeeId: coffeeId,
      methodName: methodName,
      lotId: lotId,
      methodId: methodId,
      grinderName: grinderName,
      grinderId: grinderId,
      waterProfileId: waterProfileId,
      isPreGround: isPreGround,
      grindSetting: grindSetting,
      methodToolIds: methodToolIds,
      doseGrams: doseGrams,
      frozenSource: frozenSource,
      waterGrams: waterGrams,
      beverageGrams: beverageGrams,
      timeSeconds: timeSeconds,
      temperatureC: temperatureC,
      tdsPercent: tdsPercent,
      brix: brix,
      brixFactor: brixFactor,
      grindRpm: grindRpm,
      feederRpm: feederRpm,
      pressureBar: pressureBar,
      preinfusionSeconds: preinfusionSeconds,
      bloomSeconds: bloomSeconds,
      pours: pours,
      firstDripSeconds: firstDripSeconds,
      rating: rating,
      notes: notes,
      profileName: profileName,
      brewedAt: brewedAt,
    ),
    id: id,
  )).id;

  Future<BrewSaveOutcome> saveBrewWithOutcome(
    BrewInput input, {
    String? id,
    MeticulousShot? shot,
    GaggimateShot? gaggimateShot,
    MeticulousFreePour? freePour,
    ShotCurve? curve,
    List<String>? photos,
  }) async {
    input.validate();
    return database.transaction(() async {
      final previous = await _brewTarget(
        id,
        coffeeId: input.coffeeId,
        lotId: input.lotId,
        doseGrams: input.doseGrams,
      );
      final waterProfile = await _brewWaterProfile(
        input.waterProfileId,
        previous,
      );
      await _recipient(input.recipient?.id);
      final lot = await _brewLot(input.lotId, input.coffeeId);
      final catalog = await _brewCatalog(input, previous);
      final source = await _saveBrewStock(
        previous,
        lotId: input.lotId,
        doseGrams: input.doseGrams,
        frozenSource: input.frozenSource,
      );
      final row = _brewRow(
        input,
        id: id ?? _uuid.v4(),
        previous: previous,
        catalog: catalog,
        waterProfile: waterProfile,
        source: source,
      );
      await _writeBrew(
        row,
        previous: previous,
        toolIds: catalog.toolIds,
        shot: shot,
        gaggimateShot: gaggimateShot,
        freePour: freePour,
        curve: curve,
        photos: photos,
      );
      return BrewSaveOutcome(
        id: row.id,
        coffeeId: input.coffeeId,
        overdrawIncreased: await _overdrawIncreased(lot, input.coffeeId),
      );
    });
  }

  /// Grams each lot gets back or gives when a brew is saved: a counted
  /// [previous] version returns its dose, and the new one takes [doseGrams]
  /// from [lotId]. Legacy brews awaiting stock review draw nothing.
  Map<String, double> _doseChanges(
    Brew? previous, {
    required String? lotId,
    required double? doseGrams,
  }) {
    final changes = <String, double>{};
    if (previous != null &&
        _brewAdjustsStock(previous) &&
        previous.lotId != null &&
        previous.doseGrams != null) {
      changes.update(
        previous.lotId!,
        (value) => value + previous.doseGrams!,
        ifAbsent: () => previous.doseGrams!,
      );
    }
    if ((previous == null || _brewAdjustsStock(previous)) &&
        lotId != null &&
        doseGrams != null) {
      changes.update(
        lotId,
        (value) => value - doseGrams,
        ifAbsent: () => -doseGrams,
      );
    }
    return changes;
  }

  /// Makes [toolIds] the tools selected for [brewId].
  Future<void> _replaceBrewTools(String brewId, List<String> toolIds) async {
    await (database.delete(
      database.brewToolSelections,
    )..where((selection) => selection.brewId.equals(brewId))).go();
    if (toolIds.isEmpty) return;
    await database.batch((batch) {
      batch.insertAll(database.brewToolSelections, [
        for (final toolId in toolIds)
          BrewToolSelection(brewId: brewId, toolId: toolId),
      ]);
    });
  }

  /// Whether the brew just saved overdrew [lotBefore] further and left the
  /// coffee without unfrozen or frozen stock: the moment to offer archiving it.
  Future<bool> _overdrawIncreased(CoffeeLot? lotBefore, String coffeeId) async {
    if (lotBefore == null) return false;
    final lotAfter = await (database.select(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotBefore.id))).getSingle();
    final stockBalance = await _coffeeStockBalanceForActiveLots(coffeeId);
    final frozen =
        frozenGramsByCoffee(
          await coffeeLots(coffeeId),
          await database.select(database.frozenPortions).get(),
        )[coffeeId] ??
        0;
    return (lotAfter.overdrawGrams ?? 0) >
            (lotBefore.overdrawGrams ?? 0) + 0.000001 &&
        frozen <= 0 &&
        stockBalance != null &&
        stockBalance <= 0.000001;
  }

  Future<void> setBrewArchived(String id, {required bool archived}) =>
      database.transaction(() async {
        final brew = await (database.select(
          database.brews,
        )..where((row) => row.id.equals(id))).getSingleOrNull();
        if (brew == null) throw StateError('Brew not found');
        final coffee = await (database.select(
          database.coffees,
        )..where((row) => row.id.equals(brew.coffeeId))).getSingleOrNull();
        if (coffee == null) throw StateError('Coffee not found');
        if (!archived &&
            (coffee.archivedAtMs != null || brew.archivedByCoffee == true)) {
          throw const BrewArchivedWithCoffeeException();
        }
        if ((brew.archivedAtMs != null) == archived) return;
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await (database.update(
          database.brews,
        )..where((row) => row.id.equals(id))).write(
          BrewsCompanion(
            archivedAtMs: Value(archived ? now : null),
            archivedByCoffee: const Value(false),
            updatedAtMs: Value(now),
          ),
        );
      });

  // Deleting corrects a recorded consumption, even if the brew is archived.
  // Pending legacy brews already returned their dose; never return it twice.
  // Restore an archived coffee first so its inventory can be changed openly.
  Future<List<String>> deleteBrew(String id) => database.transaction(() async {
    final brew = await this.brew(id);
    if (brew == null) throw StateError('Brew not found');
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(brew.coffeeId))).getSingleOrNull();
    if (coffee?.archivedAtMs != null || brew.archivedByCoffee == true) {
      throw const BrewArchivedWithCoffeeException();
    }
    if (_brewAdjustsStock(brew) &&
        brew.lotId != null &&
        brew.doseGrams != null) {
      await _changeBrewStock(brew, consume: false);
    }
    final files = await brewPhotos(id);
    await (database.delete(database.importRecords)..where(
          (row) => row.localEntity.equals('brew') & row.localId.equals(id),
        ))
        .go();
    // Curve, photos and tool selections go with it (foreign-key cascade).
    await (database.delete(
      database.brews,
    )..where((row) => row.id.equals(id))).go();
    final referenced = {
      for (final row in await database.select(database.coffeePhotos).get())
        row.fileName,
      for (final row in await database.select(database.brewPhotos).get())
        row.fileName,
    };
    return files.where((name) => !referenced.contains(name)).toList();
  });

  /// Records the first brew from a bag as the day it was opened, which
  /// speeds up its aging (see effectiveRoastAge).
  Future<void> _markLotOpened(String lotId, DateTime brewedAt) async {
    final lot = await (database.select(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotId))).getSingleOrNull();
    if (lot == null) return;
    final day = DateTime.utc(brewedAt.year, brewedAt.month, brewedAt.day);
    final opened = DateTime.tryParse(lot.openedDate ?? '');
    if (opened != null && !day.isBefore(opened)) return;
    await (database.update(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotId))).write(
      CoffeeLotsCompanion(
        openedDate: Value(day.toIso8601String().substring(0, 10)),
      ),
    );
  }

  Future<void> _applyStockChanges(Map<String, double> changes) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final entry in changes.entries) {
      if (entry.value == 0) continue;
      final lot = await (database.select(
        database.coffeeLots,
      )..where((row) => row.id.equals(entry.key))).getSingleOrNull();
      if (lot == null) throw StateError('Lot not found');
      final remaining = lot.remainingGrams;
      if (remaining == null) continue;
      final (nextRemaining, nextOverdraw) = _materializeBalance(
        remaining - (lot.overdrawGrams ?? 0) + entry.value,
      );
      await (database.update(
        database.coffeeLots,
      )..where((row) => row.id.equals(entry.key))).write(
        CoffeeLotsCompanion(
          remainingGrams: Value(nextRemaining),
          overdrawGrams: Value(nextOverdraw),
          updatedAtMs: Value(now),
        ),
      );
    }
  }

  Future<double?> _consumedGrams(CoffeeLot lot) async {
    final activeBrews =
        await (database.select(database.brews)..where(
              (brew) =>
                  brew.lotId.equals(lot.id) &
                  (brew.stockReviewPending.isNull() |
                      brew.stockReviewPending.equals(false)),
            ))
            .get();
    var consumed = 0.0;
    for (final brew in activeBrews) {
      final dose = brew.doseGrams;
      if (dose == null || !dose.isFinite || dose < 0) {
        return null;
      }
      consumed += dose;
    }
    return consumed;
  }

  /// Saves how a brew tasted. Scores are 0–5 and compass axes -1..1;
  /// null clears a value.
  Future<void> rateBrew(
    String id, {
    required double? rating,
    required String? notes,
    required BrewTasting tasting,
  }) async {
    _checkRating(rating, 'rating');
    tasting.validate();
    final updated =
        await (database.update(
          database.brews,
        )..where((brew) => brew.id.equals(id))).write(
          BrewsCompanion(
            rating: Value(rating),
            notes: Value(_trimOrNull(notes)),
            tasteBalance: Value(tasting.balance),
            tasteStrength: Value(tasting.strength),
            acidity: Value(tasting.acidity),
            sweetness: Value(tasting.sweetness),
            bitterness: Value(tasting.bitterness),
            body: Value(tasting.body),
            aftertaste: Value(tasting.aftertaste),
            updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          ),
        );
    if (updated == 0) throw StateError('Brew not found');
  }

  Future<Brew?> brew(String id) => (database.select(
    database.brews,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  /// Every brew of a coffee, archived ones included.
  Future<List<Brew>> brewsOfCoffee(String coffeeId) => (database.select(
    database.brews,
  )..where((row) => row.coffeeId.equals(coffeeId))).get();

  /// Makes [id] the favourite of its coffee and method, replacing the one
  /// before; [favorite] false unmarks it. Like a coffee's favourite heart,
  /// it is not an edit of the brew.
  Future<void> setBrewFavorite(String id, {required bool favorite}) =>
      database.transaction(() async {
        final brew = await this.brew(id);
        if (brew == null) throw StateError('Brew not found');
        final methodId = brew.methodId;
        if (methodId == null) throw StateError('Brew has no method');
        if (favorite) {
          await (database.update(database.brews)..where(
                (row) =>
                    row.coffeeId.equals(brew.coffeeId) &
                    row.methodId.equals(methodId) &
                    row.isFavorite.equals(true),
              ))
              .write(const BrewsCompanion(isFavorite: Value(false)));
        }
        await (database.update(database.brews)
              ..where((row) => row.id.equals(id)))
            .write(BrewsCompanion(isFavorite: Value(favorite)));
      });
}
