part of '../journal_repository.dart';

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
  }) => brews.createBrew(
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
  }) => brews.saveBrew(
    id: id,
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
  Future<BrewSaveOutcome> saveBrewWithOutcome(
    BrewInput input, {
    String? id,
    MeticulousShot? shot,
    GaggimateShot? gaggimateShot,
    MeticulousFreePour? freePour,
    ShotCurve? curve,
    List<String>? photos,
  }) => brews.saveBrewWithOutcome(
    input,
    id: id,
    shot: shot,
    gaggimateShot: gaggimateShot,
    freePour: freePour,
    curve: curve,
    photos: photos,
  );
  Future<void> setBrewArchived(String id, {required bool archived}) =>
      brews.setBrewArchived(id, archived: archived);
  Future<List<String>> deleteBrew(String id) => brews.deleteBrew(id);

  /// Saves how a brew tasted. Scores are 0–5 and compass axes -1..1;
  /// null clears a value.
  Future<void> rateBrew(
    String id, {
    required double? rating,
    required String? notes,
    required BrewTasting tasting,
  }) => brews.rateBrew(id, rating: rating, notes: notes, tasting: tasting);
  Future<Brew?> brew(String id) => records.brew(id);

  /// Every brew of a coffee, archived ones included.
  Future<List<Brew>> brewsOfCoffee(String coffeeId) =>
      records.brewsOfCoffee(coffeeId);

  /// Makes [id] the favourite of its coffee and method, replacing the one
  /// before; [favorite] false unmarks it. Like a coffee's favourite heart,
  /// it is not an edit of the brew.
  Future<void> setBrewFavorite(String id, {required bool favorite}) =>
      brews.setBrewFavorite(id, favorite: favorite);
}
