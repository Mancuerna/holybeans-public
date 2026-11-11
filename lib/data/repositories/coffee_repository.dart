import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/coffee_profile_writer.dart';
import 'package:holybeans/data/repositories/coffee_suggestions.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/data/repositories/photos_repository.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';
import 'package:holybeans/domain/flavor_notes.dart';
import 'package:holybeans/domain/web_link.dart';
import 'package:uuid/uuid.dart';

/// Coffee profiles, imported cards and their associated inventory entries.
class CoffeeRepository {
  CoffeeRepository(
    this.database,
    this._freezer,
    this._photos,
    this._profile,
    this._records,
  );
  final AppDatabase database;
  final FreezerRepository _freezer;
  final PhotoRepository _photos;
  final CoffeeProfileWriter _profile;
  final JournalRecordQueries _records;
  final Uuid _uuid = const Uuid();

  /// Reads suggestions once for a bean form, including archived coffees.
  Future<CoffeeSuggestions> coffeeSuggestions() async =>
      coffeeSuggestionsFromRows(
        await (database.select(
          database.coffees,
        )..orderBy([(row) => OrderingTerm.desc(row.updatedAtMs)])).get(),
        await database.select(database.coffeeComponents).get(),
        roasterNames: (await database.select(database.roasters).get()).map(
          (r) => r.name,
        ),
      );

  /// Deletes an unused coffee and its inventory, origins and photo references.
  /// Checks all brews again inside the transaction, archived ones included.
  /// Returns photo files no longer referenced by any coffee or brew.
  Future<List<String>> deleteUnusedCoffee(String id) =>
      database.transaction(() async {
        if (await _records.coffee(id) == null) {
          throw StateError('Coffee not found');
        }
        final brew =
            await (database.select(database.brews)
                  ..where((row) => row.coffeeId.equals(id))
                  ..limit(1))
                .getSingleOrNull();
        if (brew != null) throw const CoffeeHasBrewsException();
        final files = await _photos.coffeePhotos(id);
        final lots = await (database.select(
          database.coffeeLots,
        )..where((row) => row.coffeeId.equals(id))).get();
        for (final lot in lots) {
          await (database.delete(
            database.frozenPortions,
          )..where((row) => row.lotId.equals(lot.id))).go();
        }
        await (database.delete(
          database.coffeeLots,
        )..where((row) => row.coffeeId.equals(id))).go();
        await (database.delete(
          database.coffeeComponents,
        )..where((row) => row.coffeeId.equals(id))).go();
        // Remove the import mapping too, so a later import can add it again.
        // Its original payload is removed by the foreign-key cascade.
        await (database.delete(database.importRecords)..where(
              (row) =>
                  row.localEntity.equals('coffee') & row.localId.equals(id),
            ))
            .go();
        await (database.delete(
          database.coffees,
        )..where((row) => row.id.equals(id))).go();
        return _photos.unreferencedPhotos(files);
      });

  Future<String> createCoffee({
    required String name,
    required String roaster,
    String? country,
    String? region,
    String? farm,
    String? producer,
    String? variety,
    String? process,
    int? altitudeMeters,
    int? altitudeMaxMeters,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
  }) {
    final hasOrigin = [
      country,
      region,
      farm,
      producer,
      variety,
      process,
      altitudeMeters?.toString(),
      altitudeMaxMeters?.toString(),
    ].any((value) => trimOrNull(value) != null);
    return _createCoffee(
      name: name,
      roaster: roaster,
      components: hasOrigin
          ? [
              CoffeeComponentInput(
                country: country,
                region: region,
                farm: farm,
                producer: producer,
                variety: variety,
                process: process,
                altitudeMeters: altitudeMeters,
                altitudeMaxMeters: altitudeMaxMeters,
              ),
            ]
          : const [],
      roastDate: roastDate,
      initialGrams: initialGrams,
      paidPriceCents: paidPriceCents,
      notes: notes,
      roastLevel: roastLevel,
      flavorProfile: flavorProfile,
      restDays: restDays,
    );
  }

  /// Creates a coffee with an ordered list of origins, suitable for blends.
  /// An empty list is allowed for coffees whose origin is not recorded yet.
  /// Creates a coffee and, when [freeze] is given, freezes part or all of its
  /// purchased quantity in the same transaction.
  Future<String> createCoffeeWithComponents({
    required String name,
    required String roaster,
    required List<CoffeeComponentInput> components,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
    FreezeRequest? freeze,
    bool isDecaf = false,
    String? shopUrl,
    List<String>? photos,
  }) async => (await createCoffeeEntry(
    name: name,
    roaster: roaster,
    components: components,
    roastDate: roastDate,
    initialGrams: initialGrams,
    paidPriceCents: paidPriceCents,
    notes: notes,
    roastLevel: roastLevel,
    flavorProfile: flavorProfile,
    restDays: restDays,
    freeze: freeze,
    isDecaf: isDecaf,
    shopUrl: shopUrl,
    photos: photos,
  )).id;

  Future<({String id, String? frozenLabel})> createCoffeeEntry({
    required String name,
    required String roaster,
    required List<CoffeeComponentInput> components,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
    FreezeRequest? freeze,
    bool isDecaf = false,
    String? shopUrl,
    List<String>? photos,
  }) => database.transaction(() async {
    final coffeeId = await _createCoffee(
      name: name,
      roaster: roaster,
      components: components,
      roastDate: roastDate,
      initialGrams: initialGrams,
      paidPriceCents: paidPriceCents,
      notes: notes,
      roastLevel: roastLevel,
      flavorProfile: flavorProfile,
      restDays: restDays,
    );
    String? frozenLabel;
    if (freeze != null) {
      final lot = (await _records.coffeeLots(coffeeId)).single;
      final portionId = await _freezer.freezeCoffee(
        lotId: lot.id,
        grams: freeze.grams,
        frozenDate: freeze.frozenDate,
        container: freeze.container,
        notes: freeze.notes,
      );
      frozenLabel = (await (database.select(
        database.frozenPortions,
      )..where((row) => row.id.equals(portionId))).getSingle()).label;
    }
    await setCoffeeExtras(coffeeId, isDecaf: isDecaf, shopUrl: shopUrl);
    if (photos != null) await _photos.setCoffeePhotos(coffeeId, photos);
    return (id: coffeeId, frozenLabel: frozenLabel);
  });

  Future<String> _createCoffee({
    required String name,
    required String roaster,
    required List<CoffeeComponentInput> components,
    String? roastDate,
    double? initialGrams,
    int? paidPriceCents,
    String? notes,
    String? roastLevel,
    String? flavorProfile,
    int? restDays,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError.value(name, 'name');
    validateStockDate(roastDate);
    validatePositive(initialGrams, 'initialGrams');
    validateCoffeePrice(paidPriceCents);
    validateRoastLevel(roastLevel);
    validateRestDays(restDays);
    final cleanComponents = normalizeCoffeeComponents(components);
    if (cleanComponents.any((component) => component.id != null)) {
      throw ArgumentError('New coffee components cannot have existing IDs');
    }

    final coffeeId = _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.transaction(() async {
      await database
          .into(database.coffees)
          .insert(
            Coffee(
              id: coffeeId,
              name: cleanName,
              roaster: roaster.trim(),
              notes: trimOrNull(notes),
              paidPriceCents: paidPriceCents,
              roastLevel: roastLevel,
              flavorProfile: normalizeFlavorNotes(flavorProfile),
              restDays: restDays,
              isFavorite: false,
              isDecaf: false,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
      await RoasterRegistry(database).linkCoffee(coffeeId, roaster);
      for (var position = 0; position < cleanComponents.length; position++) {
        final component = cleanComponents[position];
        await database
            .into(database.coffeeComponents)
            .insert(
              CoffeeComponent(
                id: _uuid.v4(),
                coffeeId: coffeeId,
                position: position,
                country: component.country,
                region: component.region,
                farm: component.farm,
                producer: component.producer,
                variety: component.variety,
                process: component.process,
                altitudeMeters: component.altitudeMeters,
                altitudeMaxMeters: component.altitudeMaxMeters,
                harvest: component.harvest,
              ),
            );
      }
      await database
          .into(database.coffeeLots)
          .insert(
            CoffeeLot(
              id: _uuid.v4(),
              coffeeId: coffeeId,
              roastDate: roastDate,
              initialGrams: initialGrams,
              remainingGrams: initialGrams,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
    });
    return coffeeId;
  }

  Future<void> updateCoffee({
    required String id,
    required String name,
    required String roaster,
    String? notes,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError.value(name, 'name');
    await database.transaction(() async {
      final updated =
          await (database.update(
            database.coffees,
          )..where((coffee) => coffee.id.equals(id))).write(
            CoffeesCompanion(
              name: Value(cleanName),
              roaster: Value(roaster.trim()),
              notes: Value(trimOrNull(notes)),
              updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
      if (updated == 0) throw StateError('Coffee not found');
      await RoasterRegistry(database).linkCoffee(id, roaster);
    });
  }

  Future<void> updateCoffeeProfile({
    required String id,
    required String name,
    required String roaster,
    String? notes,
    String? country,
    String? region,
    String? farm,
    String? producer,
    String? variety,
    String? process,
    int? altitudeMeters,
    int? altitudeMaxMeters,
    required int? paidPriceCents,
    String? roastLevel,
    bool updateRoastLevel = false,
    String? flavorProfile,
    int? restDays,
    bool updateFlavorProfile = false,
    bool updateRestDays = false,
    String? inventoryLotId,
    bool createInventoryLot = false,
    String? roastDate,
    double? initialGrams,
    double? remainingGrams,
    bool updateRemainingStock = false,
    bool updateOrigin = true,
    List<CoffeeComponentInput>? originComponents,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    _profile.checkProfileEdit(
      paidPriceCents: paidPriceCents,
      roastLevel: updateRoastLevel ? roastLevel : null,
      checkRoastLevel: updateRoastLevel,
      restDays: updateRestDays ? restDays : null,
      checkRestDays: updateRestDays,
      altitudeMeters: altitudeMeters,
      altitudeMaxMeters: altitudeMaxMeters,
      inventoryLotId: inventoryLotId,
      createInventoryLot: createInventoryLot,
      roastDate: roastDate,
      initialGrams: initialGrams,
      remainingGrams: remainingGrams,
      updateRemainingStock: updateRemainingStock,
    );
    final cleanComponents = originComponents == null
        ? null
        : normalizeCoffeeComponents(originComponents);
    await database.transaction(() async {
      final updated =
          await (database.update(
            database.coffees,
          )..where((coffee) => coffee.id.equals(id))).write(
            CoffeesCompanion(
              name: Value(name.trim()),
              roaster: Value(roaster.trim()),
              notes: Value(trimOrNull(notes)),
              paidPriceCents: Value(paidPriceCents),
              roastLevel: updateRoastLevel
                  ? Value(roastLevel)
                  : const Value.absent(),
              flavorProfile: updateFlavorProfile
                  ? Value(normalizeFlavorNotes(flavorProfile))
                  : const Value.absent(),
              restDays: updateRestDays ? Value(restDays) : const Value.absent(),
              updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
      if (updated == 0) throw StateError('Coffee not found');
      await RoasterRegistry(database).linkCoffee(id, roaster);

      if (createInventoryLot) {
        await _profile.createFirstLot(
          id,
          roastDate: roastDate,
          grams: initialGrams,
        );
      } else if (inventoryLotId != null) {
        await _profile.editSingleLot(
          id,
          inventoryLotId,
          roastDate: roastDate,
          initialGrams: initialGrams,
          remainingGrams: remainingGrams,
          updateRemainingStock: updateRemainingStock,
        );
      }

      if (cleanComponents != null) {
        await _replaceCoffeeComponents(id, cleanComponents);
      } else if (updateOrigin) {
        await _profile.saveSingleOrigin(
          id,
          country: country,
          region: region,
          farm: farm,
          producer: producer,
          variety: variety,
          process: process,
          altitudeMeters: altitudeMeters,
          altitudeMaxMeters: altitudeMaxMeters,
        );
      }
    });
  }

  /// Atomically updates a coffee profile and replaces its ordered origins.
  /// Pass an empty [components] list to remove all saved origins.
  Future<void> updateCoffeeProfileWithComponents({
    required String id,
    required String name,
    required String roaster,
    required int? paidPriceCents,
    required List<CoffeeComponentInput> components,
    String? notes,
    String? roastLevel,
    bool updateRoastLevel = false,
    String? flavorProfile,
    int? restDays,
    bool updateFlavorProfile = false,
    bool updateRestDays = false,
    String? inventoryLotId,
    bool createInventoryLot = false,
    String? roastDate,
    double? initialGrams,
    double? remainingGrams,
    bool updateRemainingStock = false,
    bool? isDecaf,
    String? shopUrl,
    List<String>? photos,
  }) => database.transaction(() async {
    await updateCoffeeProfile(
      id: id,
      name: name,
      roaster: roaster,
      notes: notes,
      paidPriceCents: paidPriceCents,
      roastLevel: roastLevel,
      updateRoastLevel: updateRoastLevel,
      flavorProfile: flavorProfile,
      restDays: restDays,
      updateFlavorProfile: updateFlavorProfile,
      updateRestDays: updateRestDays,
      inventoryLotId: inventoryLotId,
      createInventoryLot: createInventoryLot,
      roastDate: roastDate,
      initialGrams: initialGrams,
      remainingGrams: remainingGrams,
      updateRemainingStock: updateRemainingStock,
      updateOrigin: false,
      originComponents: components,
    );
    if (isDecaf != null) {
      await setCoffeeExtras(id, isDecaf: isDecaf, shopUrl: shopUrl);
    }
    if (photos != null) await _photos.setCoffeePhotos(id, photos);
  });

  Future<void> _replaceCoffeeComponents(
    String coffeeId,
    List<CoffeeComponentInput> components,
  ) async {
    final existing = await _records.coffeeComponents(coffeeId);
    final existingById = {for (final row in existing) row.id: row};
    final componentIds = <String>{};
    for (final component in components) {
      final componentId = component.id;
      if (componentId == null) continue;
      if (!componentIds.add(componentId)) {
        throw ArgumentError.value(componentId, 'components', 'Duplicate ID');
      }
      if (!existingById.containsKey(componentId)) {
        throw StateError('Coffee component does not belong to this coffee');
      }
    }

    for (final row in existing.where((row) => !componentIds.contains(row.id))) {
      await (database.delete(
        database.coffeeComponents,
      )..where((component) => component.id.equals(row.id))).go();
    }

    final retained = existing.where((row) => componentIds.contains(row.id));
    final maxPosition = existing.fold<int>(
      -1,
      (max, row) => row.position > max ? row.position : max,
    );
    var temporaryPosition = maxPosition + existing.length + 1;
    for (final row in retained) {
      await (database.update(
        database.coffeeComponents,
      )..where((component) => component.id.equals(row.id))).write(
        CoffeeComponentsCompanion(position: Value(temporaryPosition++)),
      );
    }

    for (var position = 0; position < components.length; position++) {
      final input = components[position];
      final id = input.id ?? _uuid.v4();
      final row = CoffeeComponent(
        id: id,
        coffeeId: coffeeId,
        position: position,
        country: input.country,
        region: input.region,
        farm: input.farm,
        producer: input.producer,
        variety: input.variety,
        process: input.process,
        altitudeMeters: input.altitudeMeters,
        altitudeMaxMeters: input.altitudeMaxMeters,
        harvest: input.harvest,
      );
      if (input.id == null) {
        await database.into(database.coffeeComponents).insert(row);
      } else {
        await database.update(database.coffeeComponents).replace(row);
      }
    }
  }

  Future<void> setCoffeeArchived(
    String id, {
    required bool archived,
    double? rating,
  }) => database.transaction(() async {
    if (archived) validateBrewRating(rating, 'rating');
    final coffee = await (database.select(
      database.coffees,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (coffee == null) throw StateError('Coffee not found');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (database.update(
      database.coffees,
    )..where((row) => row.id.equals(id))).write(
      CoffeesCompanion(
        archivedAtMs: Value(archived ? now : null),
        rating: archived ? Value(rating) : const Value.absent(),
        updatedAtMs: Value(now),
      ),
    );

    await (database.update(database.brews)..where(
          (brew) =>
              brew.coffeeId.equals(id) &
              (archived
                  ? brew.archivedAtMs.isNull()
                  : brew.archivedByCoffee.equals(true)),
        ))
        .write(
          BrewsCompanion(
            archivedAtMs: Value(archived ? now : null),
            archivedByCoffee: Value(archived),
            updatedAtMs: Value(now),
          ),
        );
  });

  Future<void> setCoffeeFavorite(String id, {required bool favorite}) async {
    final updated =
        await (database.update(database.coffees)
              ..where((coffee) => coffee.id.equals(id)))
            .write(CoffeesCompanion(isFavorite: Value(favorite)));
    if (updated == 0) throw StateError('Coffee not found');
  }

  /// Adds the coffee a card describes, with its bag, as a new coffee;
  /// returns its ID.
  Future<String> createCoffeeFromCard(SharedBean bean) =>
      database.transaction(() async {
        final id = await createCoffeeWithComponents(
          name: bean.name,
          roaster: bean.roaster,
          components: [
            for (final origin in bean.origins)
              CoffeeComponentInput(
                country: origin.country,
                region: origin.region,
                farm: origin.farm,
                producer: origin.producer,
                variety: origin.variety,
                process: origin.process,
                altitudeMeters: origin.altitudeMeters,
                altitudeMaxMeters: origin.altitudeMaxMeters,
                harvest: origin.harvest,
              ),
          ],
          roastDate: bean.roastDate,
          initialGrams: bean.bagGrams,
          paidPriceCents: bean.priceCents,
          roastLevel: bean.roastLevel,
          flavorProfile: bean.flavorProfile,
        );
        await setCoffeeExtras(id, isDecaf: bean.decaf, shopUrl: bean.shopUrl);
        return id;
      });

  /// Whether the coffee is decaf, and its shop page; blank clears it.
  Future<void> setCoffeeExtras(
    String id, {
    required bool isDecaf,
    String? shopUrl,
  }) async {
    final String? link;
    try {
      link = normalizeWebLink(shopUrl);
    } on FormatException {
      throw ArgumentError.value(shopUrl, 'shopUrl');
    }
    final updated =
        await (database.update(
          database.coffees,
        )..where((coffee) => coffee.id.equals(id))).write(
          CoffeesCompanion(isDecaf: Value(isDecaf), shopUrl: Value(link)),
        );
    if (updated == 0) throw StateError('Coffee not found');
  }
}
