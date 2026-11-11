part of '../journal_repository.dart';

/// Coffees, their lots and origins.
extension CoffeeOperations on JournalRepository {
  Future<Coffee?> coffee(String id) => (database.select(
    database.coffees,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  /// Deletes an unused coffee and its inventory, origins and photo references.
  /// Checks all brews again inside the transaction, archived ones included.
  /// Returns photo files no longer referenced by any coffee or brew.
  Future<List<String>> deleteUnusedCoffee(String id) =>
      database.transaction(() async {
        if (await coffee(id) == null) throw StateError('Coffee not found');
        final brew =
            await (database.select(database.brews)
                  ..where((row) => row.coffeeId.equals(id))
                  ..limit(1))
                .getSingleOrNull();
        if (brew != null) throw const CoffeeHasBrewsException();
        final files = await coffeePhotos(id);
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
        return _unreferencedPhotos(files);
      });

  Future<List<CoffeeLot>> coffeeLots(String coffeeId) =>
      (database.select(database.coffeeLots)
            ..where(
              (lot) =>
                  lot.coffeeId.equals(coffeeId) & lot.archivedAtMs.isNull(),
            )
            ..orderBy([(lot) => OrderingTerm.desc(lot.createdAtMs)]))
          .get();

  Future<CoffeeLot?> coffeeLot(String lotId) => (database.select(
    database.coffeeLots,
  )..where((lot) => lot.id.equals(lotId))).getSingleOrNull();

  Future<List<CoffeeComponent>> coffeeComponents(String coffeeId) =>
      (database.select(database.coffeeComponents)
            ..where((row) => row.coffeeId.equals(coffeeId))
            ..orderBy([(row) => OrderingTerm.asc(row.position)]))
          .get();

  /// Returns the signed balance across known active lots, or null if any lot
  /// has unknown stock (or no active inventory has been recorded).
  Future<double?> coffeeStockBalance(String coffeeId) async {
    return _coffeeStockBalanceForActiveLots(coffeeId);
  }

  Future<double?> _coffeeStockBalanceForActiveLots(String coffeeId) async {
    final lots = await coffeeLots(coffeeId);
    if (lots.isEmpty || lots.any((lot) => lot.remainingGrams == null)) {
      return null;
    }
    return lots.fold<double>(
      0,
      (sum, lot) => sum + lot.remainingGrams! - (lot.overdrawGrams ?? 0),
    );
  }

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
    ].any((value) => _trimOrNull(value) != null);
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
      final lot = (await coffeeLots(coffeeId)).single;
      final portionId = await freezeCoffee(
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
    if (photos != null) await setCoffeePhotos(coffeeId, photos);
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
    _checkDate(roastDate);
    _checkPositive(initialGrams, 'initialGrams');
    _checkPrice(paidPriceCents);
    _checkRoastLevel(roastLevel);
    _checkRestDays(restDays);
    final cleanComponents = _normalizeCoffeeComponents(components);
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
              notes: _trimOrNull(notes),
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
              notes: Value(_trimOrNull(notes)),
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
    _checkProfileEdit(
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
        : _normalizeCoffeeComponents(originComponents);
    await database.transaction(() async {
      final updated =
          await (database.update(
            database.coffees,
          )..where((coffee) => coffee.id.equals(id))).write(
            CoffeesCompanion(
              name: Value(name.trim()),
              roaster: Value(roaster.trim()),
              notes: Value(_trimOrNull(notes)),
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
        await _createFirstLot(id, roastDate: roastDate, grams: initialGrams);
      } else if (inventoryLotId != null) {
        await _editSingleLot(
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
        await _saveSingleOrigin(
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
    if (photos != null) await setCoffeePhotos(id, photos);
  });

  Future<void> _replaceCoffeeComponents(
    String coffeeId,
    List<CoffeeComponentInput> components,
  ) async {
    final existing = await coffeeComponents(coffeeId);
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
    if (archived) _checkRating(rating, 'rating');
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
}
