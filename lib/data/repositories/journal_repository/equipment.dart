part of '../journal_repository.dart';

/// Methods (with their jug), tools, grinders and water profiles.
extension EquipmentOperations on JournalRepository {
  Future<String> createWaterProfile({
    required String name,
    double? ghPpmAsCaCO3,
    double? khPpmAsCaCO3,
    double? tdsPpm,
    double? ph,
    WaterMinerals minerals = const WaterMinerals(),
    String? notes,
    String? recipeJson,
  }) async {
    _validateWaterProfileValues(
      ghPpmAsCaCO3: ghPpmAsCaCO3,
      khPpmAsCaCO3: khPpmAsCaCO3,
      tdsPpm: tdsPpm,
      ph: ph,
    );
    minerals._validate();
    if (recipeJson != null) WaterRecipe.fromJson(recipeJson);
    final id = _uuid.v4();
    await database
        .into(database.waterProfiles)
        .insert(
          WaterProfile(
            id: id,
            name: _requireCatalogName(name, 'name'),
            ghPpmAsCaCO3: ghPpmAsCaCO3,
            khPpmAsCaCO3: khPpmAsCaCO3,
            tdsPpm: tdsPpm,
            ph: ph,
            calciumPpm: minerals.calcium,
            magnesiumPpm: minerals.magnesium,
            sodiumPpm: minerals.sodium,
            potassiumPpm: minerals.potassium,
            chloridePpm: minerals.chloride,
            sulfatePpm: minerals.sulfate,
            bicarbonatePpm: minerals.bicarbonate,
            recipeJson: recipeJson,
            notes: _trimOrNull(notes),
          ),
        );
    return id;
  }

  Future<void> updateWaterProfile({
    required String id,
    required String name,
    double? ghPpmAsCaCO3,
    double? khPpmAsCaCO3,
    double? tdsPpm,
    double? ph,
    WaterMinerals minerals = const WaterMinerals(),
    String? notes,
    String? recipeJson,
  }) async {
    _validateWaterProfileValues(
      ghPpmAsCaCO3: ghPpmAsCaCO3,
      khPpmAsCaCO3: khPpmAsCaCO3,
      tdsPpm: tdsPpm,
      ph: ph,
    );
    minerals._validate();
    if (recipeJson != null) WaterRecipe.fromJson(recipeJson);
    final updated =
        await (database.update(
          database.waterProfiles,
        )..where((profile) => profile.id.equals(id))).write(
          WaterProfilesCompanion(
            name: Value(_requireCatalogName(name, 'name')),
            ghPpmAsCaCO3: Value(ghPpmAsCaCO3),
            khPpmAsCaCO3: Value(khPpmAsCaCO3),
            tdsPpm: Value(tdsPpm),
            ph: Value(ph),
            calciumPpm: Value(minerals.calcium),
            magnesiumPpm: Value(minerals.magnesium),
            sodiumPpm: Value(minerals.sodium),
            potassiumPpm: Value(minerals.potassium),
            chloridePpm: Value(minerals.chloride),
            sulfatePpm: Value(minerals.sulfate),
            bicarbonatePpm: Value(minerals.bicarbonate),
            recipeJson: Value(recipeJson),
            notes: Value(_trimOrNull(notes)),
          ),
        );
    if (updated == 0) throw StateError('Water profile not found');
  }

  Future<void> setWaterProfileArchived(
    String id, {
    required bool archived,
  }) async {
    final updated =
        await (database.update(
          database.waterProfiles,
        )..where((profile) => profile.id.equals(id))).write(
          WaterProfilesCompanion(
            archivedAtMs: Value(
              archived ? DateTime.now().toUtc().millisecondsSinceEpoch : null,
            ),
          ),
        );
    if (updated == 0) throw StateError('Water profile not found');
  }

  Future<String> createMethod({
    required String name,
    String? category,
    String? templateType,
    String? notes,
    String? machine,
    String? machineAddress,
    String? vesselName,
    double? vesselGrams,
    String? defaultRecipientId,
    bool useRecipientCatalog = false,
  }) => database.transaction(() async {
    final (cleanMachine, cleanAddress) = _checkMachine(machine, machineAddress);
    final (jugName, jugGrams) = _checkJug(vesselName, vesselGrams);
    final recipient = useRecipientCatalog
        ? await _recipient(defaultRecipientId)
        : jugGrams == null
        ? null
        : await saveRecipient(name: jugName ?? name, emptyGrams: jugGrams);
    final id = _uuid.v4();
    await database
        .into(database.brewMethods)
        .insert(
          BrewMethod(
            id: id,
            name: _requireCatalogName(name, 'name'),
            category: _trimOrNull(category),
            templateType: _trimOrNull(templateType),
            notes: _trimOrNull(notes),
            machine: cleanMachine,
            machineAddress: cleanAddress,
            vesselName: recipient?.name ?? jugName,
            vesselGrams: recipient?.emptyGrams ?? jugGrams,
            defaultRecipientId: recipient?.id,
          ),
        );
    return id;
  });

  Future<void> updateMethod({
    required String id,
    required String name,
    String? category,
    String? templateType,
    String? notes,
    String? machine,
    String? machineAddress,
    String? vesselName,
    double? vesselGrams,
    String? defaultRecipientId,
    bool useRecipientCatalog = false,
  }) => database.transaction(() async {
    final (cleanMachine, cleanAddress) = _checkMachine(machine, machineAddress);
    final (jugName, jugGrams) = _checkJug(vesselName, vesselGrams);
    final recipient = useRecipientCatalog
        ? await _recipient(defaultRecipientId)
        : jugGrams == null
        ? null
        : await saveRecipient(name: jugName ?? name, emptyGrams: jugGrams);
    final updated =
        await (database.update(
          database.brewMethods,
        )..where((method) => method.id.equals(id))).write(
          BrewMethodsCompanion(
            name: Value(_requireCatalogName(name, 'name')),
            category: Value(_trimOrNull(category)),
            templateType: Value(_trimOrNull(templateType)),
            notes: Value(_trimOrNull(notes)),
            machine: Value(cleanMachine),
            machineAddress: Value(cleanAddress),
            vesselName: Value(recipient?.name ?? jugName),
            vesselGrams: Value(recipient?.emptyGrams ?? jugGrams),
            defaultRecipientId: Value(recipient?.id),
          ),
        );
    if (updated == 0) throw StateError('Method not found');
  });

  /// Remembers [plan] as the guided pour recipe of a method; null forgets
  /// it. The dose is not kept: it changes from brew to brew.
  Future<void> setMethodPourPlan(String id, PourPlan? plan) async {
    if (plan?.problem case final problem?) {
      throw ArgumentError.value(problem, 'plan');
    }
    final updated =
        await (database.update(database.brewMethods)
              ..where((method) => method.id.equals(id)))
            .write(BrewMethodsCompanion(pourPlanJson: Value(plan?.toJson())));
    if (updated == 0) throw StateError('Method not found');
  }

  Future<void> setMethodArchived(String id, {required bool archived}) async {
    final updated =
        await (database.update(
          database.brewMethods,
        )..where((method) => method.id.equals(id))).write(
          BrewMethodsCompanion(
            archivedAtMs: Value(
              archived ? DateTime.now().toUtc().millisecondsSinceEpoch : null,
            ),
          ),
        );
    if (updated == 0) throw StateError('Method not found');
  }

  Future<String> createGrinder({
    required String name,
    String? notes,
    bool hasAdjustableRpm = false,
    bool hasAdjustableFeederRpm = false,
  }) async {
    final id = _uuid.v4();
    await database
        .into(database.grinders)
        .insert(
          Grinder(
            id: id,
            name: _requireCatalogName(name, 'name'),
            notes: _trimOrNull(notes),
            hasAdjustableRpm: hasAdjustableRpm,
            hasAdjustableFeederRpm: hasAdjustableFeederRpm,
          ),
        );
    return id;
  }

  Future<void> updateGrinder({
    required String id,
    required String name,
    String? notes,
    bool? hasAdjustableRpm,
    bool? hasAdjustableFeederRpm,
  }) async {
    final updated =
        await (database.update(
          database.grinders,
        )..where((grinder) => grinder.id.equals(id))).write(
          GrindersCompanion(
            name: Value(_requireCatalogName(name, 'name')),
            notes: Value(_trimOrNull(notes)),
            hasAdjustableFeederRpm: hasAdjustableFeederRpm == null
                ? const Value.absent()
                : Value(hasAdjustableFeederRpm),
            hasAdjustableRpm: hasAdjustableRpm == null
                ? const Value.absent()
                : Value(hasAdjustableRpm),
          ),
        );
    if (updated == 0) throw StateError('Grinder not found');
  }

  Future<void> setGrinderArchived(String id, {required bool archived}) async {
    final updated =
        await (database.update(
          database.grinders,
        )..where((grinder) => grinder.id.equals(id))).write(
          GrindersCompanion(
            archivedAtMs: Value(
              archived ? DateTime.now().toUtc().millisecondsSinceEpoch : null,
            ),
          ),
        );
    if (updated == 0) throw StateError('Grinder not found');
  }

  Future<String> _findOrCreateMethod(String name, {Brew? previous}) async {
    if (previous != null && previous.methodId != null) {
      final previousMethod =
          await (database.select(database.brewMethods)
                ..where((method) => method.id.equals(previous.methodId!)))
              .getSingleOrNull();
      if (previousMethod != null &&
          (_catalogNameKey(previous.methodName) == _catalogNameKey(name) ||
              _catalogNameKey(previousMethod.name) == _catalogNameKey(name))) {
        return previousMethod.id;
      }
    }
    final key = _catalogNameKey(name);
    final all = await database.select(database.brewMethods).get();
    final active = all
        .where(
          (method) =>
              method.archivedAtMs == null &&
              _catalogNameKey(method.name) == key,
        )
        .toList();
    if (active.length == 1) return active.single.id;
    if (active.length > 1) throw StateError('Method name is ambiguous');
    return createMethod(name: name);
  }

  Future<String> _findOrCreateGrinder(String name, {Brew? previous}) async {
    if (previous != null && previous.grinderId != null) {
      final previousGrinder =
          await (database.select(database.grinders)
                ..where((grinder) => grinder.id.equals(previous.grinderId!)))
              .getSingleOrNull();
      if (previousGrinder != null &&
          (_catalogNameKey(previous.grinderName ?? '') ==
                  _catalogNameKey(name) ||
              _catalogNameKey(previousGrinder.name) == _catalogNameKey(name))) {
        return previousGrinder.id;
      }
    }
    final key = _catalogNameKey(name);
    final all = await database.select(database.grinders).get();
    final active = all
        .where(
          (grinder) =>
              grinder.archivedAtMs == null &&
              _catalogNameKey(grinder.name) == key,
        )
        .toList();
    if (active.length == 1) return active.single.id;
    if (active.length > 1) throw StateError('Grinder name is ambiguous');
    return createGrinder(name: name);
  }

  Future<String> _requireMethod(String id) async {
    final method = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (method == null) throw StateError('Method not found');
    return method.id;
  }

  Future<BrewMethod> _requireMethodRow(String id) async {
    final method = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (method == null) throw StateError('Method not found');
    return method;
  }

  Future<String> _requireGrinder(String id) async {
    final grinder = await (database.select(
      database.grinders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (grinder == null) throw StateError('Grinder not found');
    return grinder.id;
  }

  Future<Grinder> _requireGrinderRow(String id) async {
    final grinder = await (database.select(
      database.grinders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (grinder == null) throw StateError('Grinder not found');
    return grinder;
  }
}
