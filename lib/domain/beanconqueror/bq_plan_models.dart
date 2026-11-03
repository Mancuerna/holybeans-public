/// What an import from BeanConqueror plans to write: the records it adds,
/// the ones it updates and what it leaves out, as plain values the
/// repository writes and the import page shows.
library;

/// Where a record came from: its BeanConqueror ID and original JSON, kept
/// so fields HolyBeans does not use are not lost.
class BqOrigin {
  const BqOrigin(this.kind, this.externalId, this.rawJson);

  final String kind;
  final String externalId;
  final String rawJson;
}

class PlannedTool {
  const PlannedTool({
    required this.origin,
    required this.name,
    required this.archived,
  });

  final BqOrigin origin;
  final String name;
  final bool archived;
}

class PlannedMethod {
  PlannedMethod({
    required this.origin,
    required this.name,
    this.category,
    this.templateType,
    this.notes,
    this.archived = false,
    this.reuseId,
    this.tools = const [],
    this.machine,
    this.machineAddress,
  });

  final BqOrigin origin;
  final String name;
  final String? category;
  final String? templateType;

  /// The connected machine behind it, e.g. "meticulous", and its address.
  final String? machine;
  final String? machineAddress;
  final String? notes;
  final bool archived;

  /// A method of the journal with the same name, used instead of a new one.
  final String? reuseId;
  final List<PlannedTool> tools;

  /// The jug the brews weighed in, taken from the first brew that names one.
  String? vesselName;
  double? vesselGrams;
}

class PlannedGrinder {
  const PlannedGrinder({
    required this.origin,
    required this.name,
    this.notes,
    this.archived = false,
    this.hasAdjustableRpm = false,
    this.reuseId,
  });

  final BqOrigin origin;
  final String name;
  final String? notes;
  final bool archived;
  final bool hasAdjustableRpm;
  final String? reuseId;
}

class PlannedWater {
  const PlannedWater({
    required this.origin,
    required this.name,
    this.ghPpm,
    this.khPpm,
    this.tdsPpm,
    this.calciumPpm,
    this.magnesiumPpm,
    this.sodiumPpm,
    this.potassiumPpm,
    this.chloridePpm,
    this.sulfatePpm,
    this.notes,
    this.archived = false,
    this.reuseId,
  });

  final BqOrigin origin;
  final String name;
  final double? ghPpm;
  final double? khPpm;
  final double? tdsPpm;
  final double? calciumPpm;
  final double? magnesiumPpm;
  final double? sodiumPpm;
  final double? potassiumPpm;
  final double? chloridePpm;
  final double? sulfatePpm;
  final String? notes;
  final bool archived;
  final String? reuseId;
}

class PlannedComponent {
  const PlannedComponent({
    this.country,
    this.region,
    this.farm,
    this.producer,
    this.variety,
    this.process,
    this.altitudeMeters,
    this.altitudeMaxMeters,
    this.harvest,
  });

  final String? country;
  final String? region;
  final String? farm;
  final String? producer;
  final String? variety;
  final String? process;
  final int? altitudeMeters;
  final int? altitudeMaxMeters;
  final String? harvest;

  bool get isEmpty => [
    country,
    region,
    farm,
    producer,
    variety,
    process,
    altitudeMeters,
    altitudeMaxMeters,
    harvest,
  ].every((value) => value == null);
}

/// The bag, as one inventory record of its coffee.
class PlannedLot {
  const PlannedLot({
    this.roastDate,
    this.purchaseDate,
    this.openedDate,
    this.initialGrams,
    this.remainingGrams,
    this.overdrawGrams,
    this.frozenPauseDays,
  });

  final String? roastDate;
  final String? purchaseDate;
  final String? openedDate;
  final double? initialGrams;
  final double? remainingGrams;
  final double? overdrawGrams;
  final int? frozenPauseDays;
}

/// What is left of a frozen bag, in the freezer.
class PlannedPortion {
  const PlannedPortion({
    required this.label,
    required this.frozenDate,
    required this.grams,
    this.container,
    this.notes,
  });

  final String label;
  final String frozenDate;
  final double grams;
  final String? container;
  final String? notes;
}

class PlannedCoffee {
  const PlannedCoffee({
    required this.origin,
    required this.name,
    required this.roaster,
    required this.createdAtMs,
    required this.lot,
    this.notes,
    this.paidPriceCents,
    this.rating,
    this.roastLevel,
    this.flavorProfile,
    this.isFavorite = false,
    this.isDecaf = false,
    this.shopUrl,
    this.archivedAtMs,
    this.components = const [],
    this.portion,
    this.photos = const [],
  });

  final BqOrigin origin;
  final String name;
  final String roaster;
  final int createdAtMs;
  final PlannedLot lot;
  final String? notes;
  final int? paidPriceCents;
  final double? rating;
  final String? roastLevel;
  final String? flavorProfile;
  final bool isFavorite;
  final bool isDecaf;
  final String? shopUrl;
  final int? archivedAtMs;
  final List<PlannedComponent> components;
  final PlannedPortion? portion;

  /// File names of its BeanConqueror photos, in order.
  final List<String> photos;
}

/// Photos, and for a brew its flow profile, that BeanConqueror has for a
/// record imported before; each is added if the record has none here.
class PlannedUpdate {
  const PlannedUpdate({
    required this.kind,
    required this.externalId,
    this.photos = const [],
    this.flowProfile,
  });

  final String kind;
  final String externalId;
  final List<String> photos;

  /// File name of the brew's flow profile.
  final String? flowProfile;
}

class PlannedBrew {
  const PlannedBrew({
    required this.origin,
    required this.beanId,
    required this.methodName,
    required this.brewedAtMs,
    this.preparationId,
    this.millId,
    this.waterId,
    this.toolIds = const [],
    this.grinderName,
    this.waterName,
    this.grindSetting,
    this.doseGrams,
    this.waterGrams,
    this.beverageGrams,
    this.timeSeconds,
    this.temperatureC,
    this.tdsPercent,
    this.grindRpm,
    this.preinfusionSeconds,
    this.bloomSeconds,
    this.firstDripSeconds,
    this.profileName,
    this.rating,
    this.notes,
    this.archivedAtMs,
    this.photos = const [],
    this.flowProfile,
    this.isFavorite = false,
    this.isBestBrew = false,
    this.vessel,
  });

  final BqOrigin origin;

  /// The jug a filter brew was weighed in, with its empty weight.
  final ({String? name, double grams})? vessel;

  /// Marked with BeanConqueror's heart or as its best brew; one per coffee
  /// and method becomes the favourite here.
  final bool isFavorite;
  final bool isBestBrew;

  /// BeanConqueror IDs, resolved to local ones when written.
  final String beanId;
  final String? preparationId;
  final String? millId;
  final String? waterId;
  final List<String> toolIds;

  final String methodName;
  final String? grinderName;
  final String? waterName;
  final int brewedAtMs;
  final String? grindSetting;
  final double? doseGrams;
  final double? waterGrams;
  final double? beverageGrams;
  final int? timeSeconds;
  final double? temperatureC;
  final double? tdsPercent;
  final int? grindRpm;
  final int? preinfusionSeconds;
  final int? bloomSeconds;
  final int? firstDripSeconds;
  final String? profileName;
  final double? rating;
  final String? notes;

  /// Set, with the coffee's time, when its coffee is archived.
  final int? archivedAtMs;
  final List<String> photos;

  /// File name of the curve a scale or machine recorded, if any.
  final String? flowProfile;
}

/// A record imported before that changed in BeanConqueror since and was
/// not edited here: [planned] replaces what [localId] holds.
class PlannedChange<T> {
  const PlannedChange(this.localId, this.planned);

  final String localId;
  final T planned;
}

/// Something the user should know before importing.
enum BqWarning {
  /// Brews whose bean is not in the export nor imported before.
  brewWithoutBean,

  /// Brews or beans without a date.
  missingDate,
}

/// Everything an import will add, what it skips because it was imported
/// before, and what it could not read.
class BqImportPlan {
  const BqImportPlan({
    required this.methods,
    required this.grinders,
    required this.waters,
    required this.coffees,
    required this.brews,
    required this.skipped,
    required this.warnings,
    this.updates = const [],
    this.changedCoffees = const [],
    this.changedBrews = const [],
    this.conflicts = 0,
  });

  final List<PlannedMethod> methods;
  final List<PlannedGrinder> grinders;
  final List<PlannedWater> waters;
  final List<PlannedCoffee> coffees;
  final List<PlannedBrew> brews;

  /// Records imported before, by kind.
  final Map<String, int> skipped;

  /// How many records each warning affects.
  final Map<BqWarning, int> warnings;

  /// Photos and curves for beans and brews imported before.
  final List<PlannedUpdate> updates;

  /// Beans and brews changed in BeanConqueror since they were imported.
  final List<PlannedChange<PlannedCoffee>> changedCoffees;
  final List<PlannedChange<PlannedBrew>> changedBrews;

  /// Records changed both in BeanConqueror and here; HolyBeans' version
  /// stays.
  final int conflicts;

  bool get isEmpty =>
      methods.isEmpty &&
      grinders.isEmpty &&
      waters.isEmpty &&
      coffees.isEmpty &&
      brews.isEmpty &&
      updates.isEmpty &&
      changedCoffees.isEmpty &&
      changedBrews.isEmpty;

  /// Every photo file name the import refers to.
  Set<String> get photoNames => {
    for (final coffee in coffees) ...coffee.photos,
    for (final brew in brews) ...brew.photos,
    for (final update in updates) ...update.photos,
    for (final change in changedCoffees) ...change.planned.photos,
    for (final change in changedBrews) ...change.planned.photos,
  };

  /// Every flow profile file name the import refers to.
  Set<String> get curveNames => {
    for (final brew in brews) ?brew.flowProfile,
    for (final update in updates) ?update.flowProfile,
    for (final change in changedBrews) ?change.planned.flowProfile,
  };
}
