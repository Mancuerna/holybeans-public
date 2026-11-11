part of '../journal_repository.dart';

/// Method, grinder and tools a brew is saved with, resolved from what the
/// form gave (IDs or names) and from the brew being edited.
typedef _BrewCatalog = ({
  String methodId,
  BrewMethod method,
  bool methodMatchesPrevious,
  String? cleanGrinderName,
  String? grinderId,
  Grinder? grinder,
  List<String> toolIds,
});

/// The steps of [BrewOperations.saveBrewWithOutcome], in the order it runs
/// them inside its transaction: what may be saved, what it refers to, the
/// stock it moves, the row and what is attached to it.
extension _BrewSaveSteps on JournalRepository {
  /// The brew being edited, after checking that its coffee and stock may
  /// change as asked; null for a new brew.
  Future<Brew?> _brewTarget(
    String? id, {
    required String coffeeId,
    required String? lotId,
    required double? doseGrams,
  }) async {
    final previous = id == null
        ? null
        : await (database.select(
            database.brews,
          )..where((brew) => brew.id.equals(id))).getSingleOrNull();
    if (id != null && previous == null) throw StateError('Brew not found');
    final stockChanged =
        previous != null &&
        (previous.coffeeId != coffeeId ||
            previous.lotId != lotId ||
            previous.doseGrams != doseGrams);
    if (stockChanged && previous.stockReviewPending == true) {
      throw const BrewStockReviewRequiredException();
    }
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(coffeeId))).getSingleOrNull();
    if (coffee == null) throw StateError('Coffee not found');
    if (coffee.archivedAtMs != null &&
        (previous == null ||
            previous.archivedAtMs == null ||
            previous.coffeeId != coffeeId)) {
      throw const BrewCoffeeArchivedException();
    }
    if (stockChanged) {
      final sourceCoffee = previous.coffeeId == coffeeId
          ? coffee
          : await this.coffee(previous.coffeeId);
      if (sourceCoffee?.archivedAtMs != null ||
          previous.archivedByCoffee == true) {
        throw const BrewArchivedWithCoffeeException();
      }
    }
    return previous;
  }

  /// The water profile chosen, which must exist and, unless the brew
  /// already had it, not be archived.
  Future<WaterProfile?> _brewWaterProfile(
    String? waterProfileId,
    Brew? previous,
  ) async {
    if (waterProfileId == null) return null;
    final profile = await (database.select(
      database.waterProfiles,
    )..where((profile) => profile.id.equals(waterProfileId))).getSingleOrNull();
    if (profile == null) throw StateError('Water profile not found');
    if (profile.archivedAtMs != null &&
        previous?.waterProfileId != waterProfileId) {
      throw StateError('Archived water profile cannot be selected');
    }
    return profile;
  }

  /// The bag chosen, which must belong to the coffee.
  Future<CoffeeLot?> _brewLot(String? lotId, String coffeeId) async {
    if (lotId == null) return null;
    final lot = await (database.select(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotId))).getSingleOrNull();
    if (lot == null || lot.coffeeId != coffeeId) {
      throw StateError('Lot does not belong to coffee');
    }
    return lot;
  }

  /// Method, grinder and tools, creating a method or grinder named in the
  /// form when the catalog has none; an edit that keeps its method keeps
  /// its tools when none are given.
  Future<_BrewCatalog> _brewCatalog(BrewInput input, Brew? previous) async {
    final cleanMethod = input.methodName.trim();
    final methodId = input.methodId == null
        ? await _findOrCreateMethod(cleanMethod, previous: previous)
        : await _requireMethod(input.methodId!);
    final method = await _requireMethodRow(methodId);
    // An edit that keeps its method keeps the name it was saved with.
    final methodMatchesPrevious =
        previous != null &&
        (previous.methodId == methodId ||
            (previous.methodId == null &&
                catalogNameKey(previous.methodName) ==
                    catalogNameKey(cleanMethod)));
    final cleanGrinderName = trimOrNull(input.grinderName);
    final grinderId =
        input.grinderId ??
        (cleanGrinderName == null
            ? null
            : await _findOrCreateGrinder(cleanGrinderName, previous: previous));
    final grinder = grinderId == null
        ? null
        : await _requireGrinderRow(grinderId);
    final toolIds = await _resolveBrewTools(
      methodId,
      input.methodToolIds,
      previous: previous,
      keepPrevious: methodMatchesPrevious,
    );
    return (
      methodId: methodId,
      method: method,
      methodMatchesPrevious: methodMatchesPrevious,
      cleanGrinderName: cleanGrinderName,
      grinderId: grinderId,
      grinder: grinder,
      toolIds: toolIds,
    );
  }

  /// The row to write: what the form gave, the names the brew keeps for its
  /// method and grinder, and what an edit does not change (tasting, photos,
  /// archive, stock review).
  Brew _brewRow(
    BrewInput input, {
    required String id,
    required Brew? previous,
    required _BrewCatalog catalog,
    required WaterProfile? waterProfile,
    required ({String? portionId, double? grams}) source,
  }) {
    final cleanMethod = input.methodName.trim();
    final methodSnapshot = catalog.methodMatchesPrevious
        ? previous!.methodName
        : catalog.method.name;
    if (!catalog.methodMatchesPrevious &&
        catalogNameKey(catalog.method.name) != catalogNameKey(cleanMethod)) {
      throw ArgumentError.value(input.methodName, 'methodName');
    }
    final cleanGrinderName = catalog.cleanGrinderName;
    final grinderName = catalog.grinderId == null
        ? cleanGrinderName
        : cleanGrinderName ?? catalog.grinder!.name;
    final previousGrinderMatches =
        previous != null &&
        (previous.grinderId == catalog.grinderId ||
            (previous.grinderId == null &&
                catalogNameKey(previous.grinderName ?? '') ==
                    catalogNameKey(grinderName ?? '')));
    if (catalog.grinderId != null &&
        !previousGrinderMatches &&
        cleanGrinderName != null &&
        catalogNameKey(catalog.grinder!.name) !=
            catalogNameKey(cleanGrinderName)) {
      throw ArgumentError.value(input.grinderName, 'grinderName');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final pours = input.pours;
    final coffeeId = input.coffeeId;
    final waterProfileId = input.waterProfileId;
    return Brew(
      id: id,
      coffeeId: coffeeId,
      lotId: input.lotId,
      methodId: catalog.methodId,
      grinderId: catalog.grinderId,
      waterProfileId: waterProfileId,
      waterProfileName: waterProfileId == null
          ? null
          : previous?.waterProfileId == waterProfileId
          ? previous!.waterProfileName ?? waterProfile!.name
          : waterProfile!.name,
      isPreGround: input.isPreGround,
      methodName: methodSnapshot,
      grinderName: previousGrinderMatches ? previous.grinderName : grinderName,
      grindSetting: input.isPreGround ? null : trimOrNull(input.grindSetting),
      doseGrams: input.doseGrams,
      frozenPortionId: source.portionId,
      frozenDoseGrams: source.grams,
      waterGrams: input.waterGrams,
      beverageGrams: input.beverageGrams,
      recipientId: input.replaceRecipient || input.recipient != null
          ? input.recipient?.id
          : previous?.recipientId,
      recipientName: input.replaceRecipient || input.recipient != null
          ? input.recipient?.name
          : previous?.recipientName,
      recipientIsPortafilter: input.replaceRecipient || input.recipient != null
          ? input.recipient?.isPortafilter ?? false
          : previous?.recipientIsPortafilter ?? false,
      recipientGrams: input.replaceRecipient || input.recipient != null
          ? input.recipient?.grams
          : previous?.recipientGrams,
      timeSeconds: input.timeSeconds,
      temperatureC: input.temperatureC,
      tdsPercent: input.tdsPercent,
      brix: input.brix,
      brixFactor: input.brixFactor,
      feederRpm:
          !input.isPreGround && catalog.grinder?.hasAdjustableFeederRpm == true
          ? input.feederRpm
          : null,
      // RPM belongs to grinders that can change speed; other grinders and
      // pre-ground coffee never store it.
      grindRpm:
          !input.isPreGround &&
              catalog.grinderId != null &&
              catalog.grinder!.hasAdjustableRpm
          ? input.grindRpm
          : null,
      pressureBar: input.pressureBar,
      preinfusionSeconds: input.preinfusionSeconds,
      bloomSeconds: input.bloomSeconds,
      bloomCount: pours == null ? previous?.bloomCount : pours.bloomCount,
      pourCount: pours == null ? previous?.pourCount : pours.pourCount,
      pourPhasesJson: pours == null
          ? previous?.pourPhasesJson
          : pours.phasesJson,
      firstDripSeconds: input.firstDripSeconds,
      // Photos and tasting are changed separately (setBrewPhotos,
      // rateBrew); editing the recipe keeps them.
      tasteBalance: previous?.tasteBalance,
      tasteStrength: previous?.tasteStrength,
      acidity: previous?.acidity,
      sweetness: previous?.sweetness,
      bitterness: previous?.bitterness,
      body: previous?.body,
      aftertaste: previous?.aftertaste,
      rating: input.rating,
      // A favourite moved to another coffee or method is no longer the
      // one of its old pair, and its new pair may have one already.
      isFavorite:
          previous != null &&
          previous.isFavorite &&
          previous.coffeeId == coffeeId &&
          previous.methodId == catalog.methodId,
      notes: trimOrNull(input.notes),
      profileName: trimOrNull(input.profileName),
      brewedAtMs:
          (input.brewedAt ??
                  (previous == null
                      ? DateTime.now()
                      : DateTime.fromMillisecondsSinceEpoch(
                          previous.brewedAtMs,
                        )))
              .toUtc()
              .millisecondsSinceEpoch,
      createdAtMs: previous?.createdAtMs ?? now,
      updatedAtMs: now,
      stockReviewPending: previous?.stockReviewPending,
      archivedAtMs: previous?.archivedAtMs,
      archivedByCoffee: previous == null
          ? null
          : previous.coffeeId == coffeeId
          ? previous.archivedByCoffee
          : false,
    );
  }

  /// Writes [row] and what goes with it: the bag opened, the tools, the
  /// curve or machine record and the photos.
  Future<void> _writeBrew(
    Brew row, {
    required Brew? previous,
    required List<String> toolIds,
    MeticulousShot? shot,
    GaggimateShot? gaggimateShot,
    MeticulousFreePour? freePour,
    ShotCurve? curve,
    List<String>? photos,
  }) async {
    if (previous == null) {
      await database.into(database.brews).insert(row);
    } else {
      await database.update(database.brews).replace(row);
    }
    if (row.lotId case final lotId?) {
      await _markLotOpened(
        lotId,
        DateTime.fromMillisecondsSinceEpoch(row.brewedAtMs),
      );
    }
    await _replaceBrewTools(row.id, toolIds);
    if (gaggimateShot != null) {
      await attachGaggimateShot(row.id, gaggimateShot);
    } else if (shot != null) {
      await attachMeticulousShot(row.id, shot);
    } else if (freePour != null) {
      await attachMeticulousFreePour(row.id, freePour);
    } else if (curve != null) {
      await saveScaleCurve(row.id, curve);
    }
    if (photos != null) await setBrewPhotos(row.id, photos);
  }
}
