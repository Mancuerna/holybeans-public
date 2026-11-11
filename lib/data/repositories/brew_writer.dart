import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/equipment_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/data/repositories/photos_repository.dart';
import 'package:holybeans/data/repositories/recordings_repository.dart';
import 'package:holybeans/data/repositories/tools_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Method, grinder and tools a brew is saved with, resolved from what the
/// form gave (IDs or names) and from the brew being edited.
typedef BrewCatalog = ({
  String methodId,
  BrewMethod method,
  bool methodMatchesPrevious,
  String? cleanGrinderName,
  String? grinderId,
  Grinder? grinder,
  List<String> toolIds,
});

/// Resolves brew references and writes the row with its attached records.
class BrewWriter {
  BrewWriter(
    this.database,
    this._equipment,
    this._photos,
    this._recordings,
    this._records,
    this._tools,
  );
  final AppDatabase database;
  final EquipmentRepository _equipment;
  final PhotoRepository _photos;
  final RecordingRepository _recordings;
  final JournalRecordQueries _records;
  final ToolRepository _tools;

  /// The brew being edited, after checking that its coffee and stock may
  /// change as asked; null for a new brew.
  Future<Brew?> brewTarget(
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
          : await _records.coffee(previous.coffeeId);
      if (sourceCoffee?.archivedAtMs != null ||
          previous.archivedByCoffee == true) {
        throw const BrewArchivedWithCoffeeException();
      }
    }
    return previous;
  }

  /// The water profile chosen, which must exist and, unless the brew
  /// already had it, not be archived.
  Future<WaterProfile?> brewWaterProfile(
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
  Future<CoffeeLot?> brewLot(String? lotId, String coffeeId) async {
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
  Future<BrewCatalog> brewCatalog(BrewInput input, Brew? previous) async {
    final cleanMethod = input.methodName.trim();
    final methodId = input.methodId == null
        ? await _equipment.findOrCreateMethod(cleanMethod, previous: previous)
        : await _equipment.requireMethod(input.methodId!);
    final method = await _equipment.requireMethodRow(methodId);
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
            : await _equipment.findOrCreateGrinder(
                cleanGrinderName,
                previous: previous,
              ));
    final grinder = grinderId == null
        ? null
        : await _equipment.requireGrinderRow(grinderId);
    final toolIds = await _tools.resolveBrewTools(
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
  Brew brewRow(
    BrewInput input, {
    required String id,
    required Brew? previous,
    required BrewCatalog catalog,
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
  Future<void> writeBrew(
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
      await _recordings.attachGaggimateShot(row.id, gaggimateShot);
    } else if (shot != null) {
      await _recordings.attachMeticulousShot(row.id, shot);
    } else if (freePour != null) {
      await _recordings.attachMeticulousFreePour(row.id, freePour);
    } else if (curve != null) {
      await _recordings.saveScaleCurve(row.id, curve);
    }
    if (photos != null) await _photos.setBrewPhotos(row.id, photos);
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
}
