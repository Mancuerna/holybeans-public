import 'dart:math';

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_recipe_context.dart';
import 'package:holybeans/data/repositories/brew_recipe_queries.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/data/repositories/live_brews.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/domain/favorite_brews.dart';
import 'package:holybeans/domain/flavor_notes.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/profile_suggestions.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/domain/tool_catalog.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/web_link.dart';
import 'package:uuid/uuid.dart';

part 'journal_repository/beanconqueror.dart';
part 'journal_repository/bq_writer.dart';
part 'journal_repository/brew_save.dart';
part 'journal_repository/brews.dart';
part 'journal_repository/stock_review.dart';
part 'journal_repository/stock_adjustments.dart';
part 'journal_repository/coffees.dart';
part 'journal_repository/coffee_cards.dart';
part 'journal_repository/coffee_profile.dart';
part 'journal_repository/cupping.dart';
part 'journal_repository/equipment.dart';
part 'journal_repository/equipment_deletion.dart';
part 'journal_repository/recipients.dart';
part 'journal_repository/freezer.dart';
part 'journal_repository/frozen_brews.dart';
part 'journal_repository/imports.dart';
part 'journal_repository/photos.dart';
part 'journal_repository/tools.dart';

class BrewStockReviewRequiredException implements Exception {
  const BrewStockReviewRequiredException();
}

class BrewArchivedWithCoffeeException implements Exception {
  const BrewArchivedWithCoffeeException();
}

class BrewCoffeeArchivedException implements Exception {
  const BrewCoffeeArchivedException();
}

class CoffeeHasBrewsException implements Exception {
  const CoffeeHasBrewsException();
}

class BrewSaveOutcome {
  const BrewSaveOutcome({
    required this.id,
    required this.coffeeId,
    required this.overdrawIncreased,
  });

  final String id;
  final String coffeeId;
  final bool overdrawIncreased;
}

/// The origin and processing details for one part of a coffee blend.
///
/// [id] is optional when creating a component. For profile edits, pass the
/// existing row ID to preserve that component's identity while reordering it.
class CoffeeComponentInput {
  const CoffeeComponentInput({
    this.id,
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

  final String? id;
  final String? country;
  final String? region;
  final String? farm;
  final String? producer;
  final String? variety;
  final String? process;
  final int? altitudeMeters;
  final int? altitudeMaxMeters;

  /// When it was harvested, as written ("2025", "Jan 2025").
  final String? harvest;

  CoffeeComponentInput _normalized() {
    final clean = CoffeeComponentInput(
      id: _trimOrNull(id),
      country: _trimOrNull(country),
      region: _trimOrNull(region),
      farm: _trimOrNull(farm),
      producer: _trimOrNull(producer),
      variety: _trimOrNull(variety),
      process: _trimOrNull(process),
      altitudeMeters: altitudeMeters,
      altitudeMaxMeters: altitudeMaxMeters,
      harvest: _trimOrNull(harvest),
    );
    if (id != null && clean.id == null) {
      throw ArgumentError.value(id, 'id', 'Component ID cannot be blank');
    }
    if (!validAltitudeRange(clean.altitudeMeters, clean.altitudeMaxMeters)) {
      throw ArgumentError('Invalid altitude range');
    }
    if ([
      clean.country,
      clean.region,
      clean.farm,
      clean.producer,
      clean.variety,
      clean.process,
      clean.altitudeMeters?.toString(),
      clean.harvest,
    ].every((value) => value == null)) {
      throw ArgumentError('Each coffee component must contain origin data');
    }
    return clean;
  }
}

/// Dissolved minerals of a water profile, in ppm (mg/l) of each ion.
class WaterMinerals {
  const WaterMinerals({
    this.calcium,
    this.magnesium,
    this.sodium,
    this.potassium,
    this.chloride,
    this.sulfate,
    this.bicarbonate,
  });

  final double? calcium;
  final double? magnesium;
  final double? sodium;
  final double? potassium;
  final double? chloride;
  final double? sulfate;
  final double? bicarbonate;

  void _validate() {
    for (final (value, name) in [
      (calcium, 'calcium'),
      (magnesium, 'magnesium'),
      (sodium, 'sodium'),
      (potassium, 'potassium'),
      (chloride, 'chloride'),
      (sulfate, 'sulfate'),
      (bicarbonate, 'bicarbonate'),
    ]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw ArgumentError.value(value, name);
      }
    }
  }
}

/// Tasting notes of a brew: the extraction compass and flavour scores.
class BrewTasting {
  const BrewTasting({
    this.balance,
    this.strength,
    this.acidity,
    this.sweetness,
    this.bitterness,
    this.body,
    this.aftertaste,
  });

  factory BrewTasting.of(Brew brew) => BrewTasting(
    balance: brew.tasteBalance,
    strength: brew.tasteStrength,
    acidity: brew.acidity,
    sweetness: brew.sweetness,
    bitterness: brew.bitterness,
    body: brew.body,
    aftertaste: brew.aftertaste,
  );

  /// -1 sour, 0 balanced, 1 bitter.
  final int? balance;

  /// -1 weak, 0 balanced, 1 strong.
  final int? strength;
  final int? acidity;
  final int? sweetness;
  final int? bitterness;
  final int? body;
  final int? aftertaste;

  List<int?> get scores => [acidity, sweetness, bitterness, body, aftertaste];

  bool get isEmpty =>
      balance == null && strength == null && scores.every((s) => s == null);

  void validate() {
    for (final (value, name) in [
      (balance, 'balance'),
      (strength, 'strength'),
    ]) {
      if (value != null && (value < -1 || value > 1)) {
        throw ArgumentError.value(value, name);
      }
    }
    for (final score in scores) {
      if (score != null && (score < 0 || score > 5)) {
        throw ArgumentError.value(score, 'score');
      }
    }
  }
}

/// Coffee to freeze right after it is added.
class FreezeRequest {
  const FreezeRequest({
    required this.grams,
    required this.frozenDate,
    this.container,
    this.notes,
  });

  final double grams;

  /// Local calendar date, ISO `yyyy-MM-dd`.
  final String frozenDate;
  final String? container;
  final String? notes;
}

class JournalRepository {
  JournalRepository(this.database);

  late final CafeRepository cafes = CafeRepository(database);

  final AppDatabase database;
  late final _liveBrews = LiveBrewStore(database);
  late final PistonRepository piston = PistonRepository(database);
  late final _recipeQueries = BrewRecipeQueries(
    database,
    readToolIds: brewToolIds,
  );

  Future<Brew?> latestBrewFor({
    required String coffeeId,
    required String methodId,
    bool rated = false,
  }) => _recipeQueries.latestBrewFor(
    coffeeId: coffeeId,
    methodId: methodId,
    rated: rated,
  );

  Future<Brew?> favoriteBrewFor({
    required String coffeeId,
    required String methodId,
  }) => _recipeQueries.favoriteBrewFor(coffeeId: coffeeId, methodId: methodId);

  Future<Brew?> latestBrewForMethod(String methodId) =>
      _recipeQueries.latestBrewForMethod(methodId);

  Future<BrewReferences> dialInFor({
    required String coffeeId,
    required String methodId,
  }) => _recipeQueries.dialInFor(coffeeId: coffeeId, methodId: methodId);

  Future<BrewRecipeMemory?> methodMemory({
    required String? coffeeId,
    required String methodId,
  }) => _recipeQueries.methodMemory(coffeeId: coffeeId, methodId: methodId);

  final Uuid _uuid = const Uuid();

  Stream<List<Coffee>> watchCoffees({bool includeArchived = false}) {
    final query = database.select(database.coffees);
    if (!includeArchived) {
      query.where((coffee) => coffee.archivedAtMs.isNull());
    }
    query.orderBy([(coffee) => OrderingTerm.asc(coffee.name)]);
    return query.watch();
  }

  Stream<List<Brew>> watchBrews({bool includeArchived = false}) =>
      _liveBrews.watch(includeArchived: includeArchived);

  /// Everything the journal holds, archived records included, read once
  /// (for exports).
  Future<List<Coffee>> allCoffees() => database.select(database.coffees).get();
  Future<List<Brew>> allBrews() => database.select(database.brews).get();
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

  Future<List<BrewMethod>> allMethods() => (database.select(
    database.brewMethods,
  )..orderBy([(method) => OrderingTerm.asc(method.name)])).get();
  Future<List<CoffeeLot>> allLots() =>
      database.select(database.coffeeLots).get();

  /// Fresh stock and dose history after saving; reads do not depend on streams
  /// having delivered the transaction yet.
  Future<StockArchiveSuggestion?> archiveSuggestionForBrew(String brewId) =>
      database.transaction(() async {
        final savedBrew = await brew(brewId);
        if (savedBrew == null) return null;
        final savedCoffee = await coffee(savedBrew.coffeeId);
        if (savedCoffee == null) return null;
        return stockArchiveSuggestion(
          coffee: savedCoffee,
          brew: savedBrew,
          history: await brewsOfCoffee(savedCoffee.id),
          lots: await coffeeLots(savedCoffee.id),
          portions: await database.select(database.frozenPortions).get(),
        );
      });

  /// Reads suggestions once for a bean form, including archived coffees.
  Future<CoffeeSuggestions> coffeeSuggestions() async => CoffeeSuggestions(
    await (database.select(
      database.coffees,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAtMs)])).get(),
    await database.select(database.coffeeComponents).get(),
    roasterNames: (await database.select(database.roasters).get()).map(
      (r) => r.name,
    ),
  );

  /// Every inventory record, archived ones included.
  Stream<List<CoffeeLot>> watchLots() =>
      database.select(database.coffeeLots).watch();

  /// Every coffee's origins, in their order.
  Stream<List<CoffeeComponent>> watchComponents() => (database.select(
    database.coffeeComponents,
  )..orderBy([(row) => OrderingTerm.asc(row.position)])).watch();

  Stream<List<BrewMethod>> watchMethods({bool includeArchived = false}) {
    final query = database.select(database.brewMethods);
    if (!includeArchived) {
      query.where((method) => method.archivedAtMs.isNull());
    }
    query.orderBy([(method) => OrderingTerm.asc(method.name)]);
    return query.watch();
  }

  Stream<List<Grinder>> watchGrinders({bool includeArchived = false}) {
    final query = database.select(database.grinders);
    if (!includeArchived) {
      query.where((grinder) => grinder.archivedAtMs.isNull());
    }
    query.orderBy([(grinder) => OrderingTerm.asc(grinder.name)]);
    return query.watch();
  }

  Stream<List<WaterProfile>> watchWaterProfiles({
    bool includeArchived = false,
  }) {
    final query = database.select(database.waterProfiles);
    if (!includeArchived) {
      query.where((profile) => profile.archivedAtMs.isNull());
    }
    query.orderBy([(profile) => OrderingTerm.asc(profile.name)]);
    return query.watch();
  }

  /// Container kinds offered when freezing coffee.
  static const frozenContainers = [
    'vacuum_bag',
    'tube',
    'zip_bag',
    'jar',
    'container',
    'original_bag',
    'other',
  ];

  final Random _labelRandom = Random();
}

(double, double) _materializeBalance(double balance) {
  if (!balance.isFinite) throw ArgumentError.value(balance, 'balance');
  final normalized = balance.abs() < 0.000001 ? 0.0 : balance;
  return (normalized > 0 ? normalized : 0, normalized < 0 ? -normalized : 0);
}

void _checkRating(double? rating, String name) {
  if (rating == null) return;
  final doubled = rating * 2;
  if (!rating.isFinite ||
      rating < 0 ||
      rating > 10 ||
      (doubled - doubled.round()).abs() > 0.000001) {
    throw ArgumentError.value(rating, name);
  }
}

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _requireCatalogName(String name, String field) {
  final clean = name.trim();
  if (clean.isEmpty || clean.length > 120) {
    throw ArgumentError.value(name, field);
  }
  return clean;
}

String _catalogNameKey(String name) => name.trim().toLowerCase();

void _checkPositive(double? value, String field) {
  if (value != null && (!value.isFinite || value <= 0)) {
    throw ArgumentError.value(value, field);
  }
}

void _validateWaterProfileValues({
  required double? ghPpmAsCaCO3,
  required double? khPpmAsCaCO3,
  required double? tdsPpm,
  required double? ph,
}) {
  for (final entry in {
    'ghPpmAsCaCO3': ghPpmAsCaCO3,
    'khPpmAsCaCO3': khPpmAsCaCO3,
    'tdsPpm': tdsPpm,
  }.entries) {
    final value = entry.value;
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(value, entry.key);
    }
  }
  if (ph != null && (!ph.isFinite || ph < 0 || ph > 14)) {
    throw ArgumentError.value(ph, 'ph');
  }
}

/// A method's jug: its empty weight, and a name only alongside it.
(String?, double?) _checkJug(String? name, double? grams) {
  if (grams == null) return (null, null);
  if (!grams.isFinite || grams <= 0 || grams > 10000) {
    throw ArgumentError.value(grams, 'vesselGrams');
  }
  final cleanName = _trimOrNull(name);
  if (cleanName != null && cleanName.length > 120) {
    throw ArgumentError.value(name, 'vesselName');
  }
  return (cleanName, grams);
}

const _gramsTolerance = 1e-6;

const _labelAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/// Visible unfrozen balance of a lot, or null when it is unknown.
double? _freshGrams(CoffeeLot lot) {
  final remaining = lot.remainingGrams;
  if (remaining == null) return null;
  final balance = remaining - (lot.overdrawGrams ?? 0);
  return balance < 0 ? 0 : balance;
}

double _roundGrams(num grams) => (grams * 1000).round() / 1000;

void _checkPositiveGrams(double value, String name) {
  if (!value.isFinite || value <= 0) throw ArgumentError.value(value, name);
}

void _checkContainer(String? value) {
  if (value != null && !JournalRepository.frozenContainers.contains(value)) {
    throw ArgumentError.value(value, 'container');
  }
}

void _checkRestDays(int? value) {
  if (value != null && (value < 0 || value > 365)) {
    throw ArgumentError.value(value, 'restDays');
  }
}

void _checkPrice(int? value) {
  if (value != null && value < 0) {
    throw ArgumentError.value(value, 'paidPriceCents');
  }
}

void _checkRoastLevel(String? value) {
  const valid = {'dark', 'medium', 'omni', 'light', 'ultra_light'};
  if (value != null && !valid.contains(value)) {
    throw ArgumentError.value(value, 'roastLevel');
  }
}

void _checkDate(String? value) {
  if (value == null) return;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'roastDate');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw ArgumentError.value(value, 'roastDate');
  }
}

List<CoffeeComponentInput> _normalizeCoffeeComponents(
  List<CoffeeComponentInput> components,
) {
  final normalized = components
      .map((component) => component._normalized())
      .toList(growable: false);
  final ids = normalized
      .map((component) => component.id)
      .whereType<String>()
      .toList(growable: false);
  if (ids.toSet().length != ids.length) {
    throw ArgumentError.value(components, 'components', 'IDs must be unique');
  }
  return normalized;
}

/// Machines a method can be connected to.
const connectedMachines = {'meticulous', 'gaggimate'};

/// Validates a method's machine and address: the machine must be a known
/// one and its address a valid host, and there is no address without one.
(String?, String?) _checkMachine(String? machine, String? address) {
  final cleanMachine = _trimOrNull(machine);
  if (cleanMachine == null) return (null, null);
  if (!connectedMachines.contains(cleanMachine)) {
    throw ArgumentError.value(machine, 'machine');
  }
  final cleanAddress = _trimOrNull(address);
  if (cleanAddress != null) {
    try {
      if (cleanMachine == 'gaggimate') {
        GaggimateClient.normalizeAddress(cleanAddress);
      } else {
        MeticulousClient.normalizeAddress(cleanAddress);
      }
    } on FormatException {
      throw ArgumentError.value(address, 'machineAddress');
    }
  }
  return (cleanMachine, cleanAddress);
}
