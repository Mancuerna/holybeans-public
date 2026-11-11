import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stock_ledger.dart';
import 'package:holybeans/data/repositories/brew_writer.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/data/repositories/photos_repository.dart';
import 'package:holybeans/data/repositories/recipients_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/profile_suggestions.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:uuid/uuid.dart';

/// Brew commands coordinate catalog resolution, stock and recorded details.
class BrewRepository {
  BrewRepository(
    this.database,
    this._photos,
    this._recipients,
    this._records,
    this._stock,
    this._writer,
  );
  final AppDatabase database;
  final PhotoRepository _photos;
  final RecipientRepository _recipients;
  final JournalRecordQueries _records;
  final BrewStockLedger _stock;
  final BrewWriter _writer;
  final Uuid _uuid = const Uuid();

  Future<ProfileSuggestions> profileSuggestions() async {
    final brews = database.brews;
    final query = database.selectOnly(brews)
      ..addColumns([brews.profileName, brews.methodId, brews.brewedAtMs])
      ..where(brews.profileName.isNotNull());
    return ProfileSuggestions([
      for (final row in await query.get())
        (
          name: row.read(brews.profileName)!,
          methodId: row.read(brews.methodId),
          brewedAtMs: row.read(brews.brewedAtMs)!,
        ),
    ]);
  }

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
      final previous = await _writer.brewTarget(
        id,
        coffeeId: input.coffeeId,
        lotId: input.lotId,
        doseGrams: input.doseGrams,
      );
      final waterProfile = await _writer.brewWaterProfile(
        input.waterProfileId,
        previous,
      );
      final recipient = await _recipients.requireRecipient(input.recipient?.id);
      if (recipient != null &&
          recipient.isPortafilter != input.recipient!.isPortafilter) {
        throw ArgumentError('Recipient use does not match catalog');
      }
      final lot = await _writer.brewLot(input.lotId, input.coffeeId);
      final catalog = await _writer.brewCatalog(input, previous);
      if (recipient?.isPortafilter == true &&
          !isEspressoMethod(
            category: catalog.method.category,
            methodName: catalog.method.name,
          )) {
        throw ArgumentError('A portafilter requires an espresso method');
      }
      final source = await _stock.saveBrewStock(
        previous,
        lotId: input.lotId,
        doseGrams: input.doseGrams,
        frozenSource: input.frozenSource,
      );
      final row = _writer.brewRow(
        input,
        id: id ?? _uuid.v4(),
        previous: previous,
        catalog: catalog,
        waterProfile: waterProfile,
        source: source,
      );
      await _writer.writeBrew(
        row,
        previous: previous,
        toolIds: catalog.toolIds,
        shot: shot,
        gaggimateShot: gaggimateShot,
        freePour: freePour,
        curve: curve,
        photos: photos,
      );
      if (previous == null &&
          input.recipient?.isPortafilter == true &&
          recipient?.archivedAtMs == null) {
        await (database.update(
          database.brewMethods,
        )..where((m) => m.id.equals(catalog.methodId))).write(
          BrewMethodsCompanion(
            defaultRecipientId: Value(recipient!.id),
            vesselName: Value(recipient.name),
            vesselGrams: Value(recipient.emptyGrams),
          ),
        );
      }
      return BrewSaveOutcome(
        id: row.id,
        coffeeId: input.coffeeId,
        overdrawIncreased: await _overdrawIncreased(lot, input.coffeeId),
      );
    });
  }

  /// Whether the brew just saved overdrew [lotBefore] further and left the
  /// coffee without unfrozen or frozen stock: the moment to offer archiving it.
  Future<bool> _overdrawIncreased(CoffeeLot? lotBefore, String coffeeId) async {
    if (lotBefore == null) return false;
    final lotAfter = await (database.select(
      database.coffeeLots,
    )..where((row) => row.id.equals(lotBefore.id))).getSingle();
    final stockBalance = await _stock.coffeeStockBalanceForActiveLots(coffeeId);
    final frozen =
        frozenGramsByCoffee(
          await _records.coffeeLots(coffeeId),
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

  Future<List<String>> deleteBrew(String id) => database.transaction(() async {
    final brew = await _records.brew(id);
    if (brew == null) throw StateError('Brew not found');
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(brew.coffeeId))).getSingleOrNull();
    if (coffee?.archivedAtMs != null || brew.archivedByCoffee == true) {
      throw const BrewArchivedWithCoffeeException();
    }
    if (brewAdjustsStock(brew) &&
        brew.lotId != null &&
        brew.doseGrams != null) {
      await _stock.changeBrewStock(brew, consume: false);
    }
    final files = await _photos.brewPhotos(id);
    await (database.delete(database.importRecords)..where(
          (row) => row.localEntity.equals('brew') & row.localId.equals(id),
        ))
        .go();
    // Curve, photos and tool selections go with it (foreign-key cascade).
    await (database.delete(
      database.brews,
    )..where((row) => row.id.equals(id))).go();
    return _photos.unreferencedPhotos(files);
  });

  /// Saves how a brew tasted. Scores are 0–5 and compass axes -1..1;
  /// null clears a value.
  Future<void> rateBrew(
    String id, {
    required double? rating,
    required String? notes,
    required BrewTasting tasting,
  }) async {
    validateBrewRating(rating, 'rating');
    tasting.validate();
    final updated =
        await (database.update(
          database.brews,
        )..where((brew) => brew.id.equals(id))).write(
          BrewsCompanion(
            rating: Value(rating),
            notes: Value(trimOrNull(notes)),
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

  /// Makes [id] the favourite of its coffee and method, replacing the one
  /// before; [favorite] false unmarks it. Like a coffee's favourite heart,
  /// it is not an edit of the brew.
  Future<void> setBrewFavorite(String id, {required bool favorite}) =>
      database.transaction(() async {
        final brew = await _records.brew(id);
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
