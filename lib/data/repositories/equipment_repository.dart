import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/recipients_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:uuid/uuid.dart';

enum EquipmentDeletionBlocker { brews, tools, machine, recipient, cupping }

class EquipmentInUseException implements Exception {
  EquipmentInUseException(Iterable<EquipmentDeletionBlocker> blockers)
    : blockers = List.unmodifiable(blockers);

  final List<EquipmentDeletionBlocker> blockers;
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

/// Methods, grinders, water profiles and their deletion constraints.
class EquipmentRepository {
  EquipmentRepository(this.database, this.recipients);
  final AppDatabase database;
  final Uuid _uuid = const Uuid();
  final RecipientRepository recipients;

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
    validateWaterProfileValues(
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
            name: requireCatalogName(name, 'name'),
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
            notes: trimOrNull(notes),
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
    validateWaterProfileValues(
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
            name: Value(requireCatalogName(name, 'name')),
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
            notes: Value(trimOrNull(notes)),
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
    final (cleanMachine, cleanAddress) = checkMachine(machine, machineAddress);
    final (jugName, jugGrams) = checkJug(vesselName, vesselGrams);
    final recipient = useRecipientCatalog
        ? await recipients.requireRecipient(defaultRecipientId)
        : jugGrams == null
        ? null
        : await recipients.saveRecipient(
            name: jugName ?? name,
            emptyGrams: jugGrams,
          );
    if (recipient != null &&
        recipient.isPortafilter != (category == 'espresso')) {
      throw ArgumentError('Recipient use does not match method');
    }
    final id = _uuid.v4();
    await database
        .into(database.brewMethods)
        .insert(
          BrewMethod(
            id: id,
            name: requireCatalogName(name, 'name'),
            category: trimOrNull(category),
            templateType: trimOrNull(templateType),
            notes: trimOrNull(notes),
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
    final (cleanMachine, cleanAddress) = checkMachine(machine, machineAddress);
    final (jugName, jugGrams) = checkJug(vesselName, vesselGrams);
    final recipient = useRecipientCatalog
        ? await recipients.requireRecipient(defaultRecipientId)
        : jugGrams == null
        ? null
        : await recipients.saveRecipient(
            name: jugName ?? name,
            emptyGrams: jugGrams,
          );
    if (recipient != null &&
        recipient.isPortafilter != (category == 'espresso')) {
      throw ArgumentError('Recipient use does not match method');
    }
    final updated =
        await (database.update(
          database.brewMethods,
        )..where((method) => method.id.equals(id))).write(
          BrewMethodsCompanion(
            name: Value(requireCatalogName(name, 'name')),
            category: Value(trimOrNull(category)),
            templateType: Value(trimOrNull(templateType)),
            notes: Value(trimOrNull(notes)),
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
            name: requireCatalogName(name, 'name'),
            notes: trimOrNull(notes),
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
            name: Value(requireCatalogName(name, 'name')),
            notes: Value(trimOrNull(notes)),
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

  Future<String> findOrCreateMethod(String name, {Brew? previous}) async {
    if (previous != null && previous.methodId != null) {
      final previousMethod =
          await (database.select(database.brewMethods)
                ..where((method) => method.id.equals(previous.methodId!)))
              .getSingleOrNull();
      if (previousMethod != null &&
          (catalogNameKey(previous.methodName) == catalogNameKey(name) ||
              catalogNameKey(previousMethod.name) == catalogNameKey(name))) {
        return previousMethod.id;
      }
    }
    final key = catalogNameKey(name);
    final all = await database.select(database.brewMethods).get();
    final active = all
        .where(
          (method) =>
              method.archivedAtMs == null && catalogNameKey(method.name) == key,
        )
        .toList();
    if (active.length == 1) return active.single.id;
    if (active.length > 1) throw StateError('Method name is ambiguous');
    return createMethod(name: name);
  }

  Future<String> findOrCreateGrinder(String name, {Brew? previous}) async {
    if (previous != null && previous.grinderId != null) {
      final previousGrinder =
          await (database.select(database.grinders)
                ..where((grinder) => grinder.id.equals(previous.grinderId!)))
              .getSingleOrNull();
      if (previousGrinder != null &&
          (catalogNameKey(previous.grinderName ?? '') == catalogNameKey(name) ||
              catalogNameKey(previousGrinder.name) == catalogNameKey(name))) {
        return previousGrinder.id;
      }
    }
    final key = catalogNameKey(name);
    final all = await database.select(database.grinders).get();
    final active = all
        .where(
          (grinder) =>
              grinder.archivedAtMs == null &&
              catalogNameKey(grinder.name) == key,
        )
        .toList();
    if (active.length == 1) return active.single.id;
    if (active.length > 1) throw StateError('Grinder name is ambiguous');
    return createGrinder(name: name);
  }

  Future<String> requireMethod(String id) async {
    final method = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (method == null) throw StateError('Method not found');
    return method.id;
  }

  Future<BrewMethod> requireMethodRow(String id) async {
    final method = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (method == null) throw StateError('Method not found');
    return method;
  }

  Future<String> requireGrinder(String id) async {
    final grinder = await (database.select(
      database.grinders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (grinder == null) throw StateError('Grinder not found');
    return grinder.id;
  }

  Future<Grinder> requireGrinderRow(String id) async {
    final grinder = await (database.select(
      database.grinders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (grinder == null) throw StateError('Grinder not found');
    return grinder;
  }

  Future<List<EquipmentDeletionBlocker>> methodDeletionBlockers(String id) =>
      database.transaction(() => _methodDeletionBlockers(id));

  Future<List<EquipmentDeletionBlocker>> _methodDeletionBlockers(
    String id,
  ) async {
    final method = await (database.select(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (method == null) throw StateError('Method not found');
    final brew =
        await (database.select(database.brews)
              ..where((row) => row.methodId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    final toolLink =
        await (database.select(database.toolMethodLinks)
              ..where((row) => row.methodId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    // Original ownership remains a reference even after dissociation or merge.
    final legacyTool =
        await (database.select(database.methodTools)
              ..where((row) => row.methodId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    final machineLink = await (database.select(
      database.pistonMethodLinks,
    )..where((row) => row.methodId.equals(id))).getSingleOrNull();
    return [
      if (brew != null) EquipmentDeletionBlocker.brews,
      if (toolLink != null || legacyTool != null)
        EquipmentDeletionBlocker.tools,
      if (machineLink != null) EquipmentDeletionBlocker.machine,
      if (method.defaultRecipientId != null) EquipmentDeletionBlocker.recipient,
    ];
  }

  Future<List<EquipmentDeletionBlocker>> waterProfileDeletionBlockers(
    String id,
  ) => database.transaction(() => _waterProfileDeletionBlockers(id));

  Future<List<EquipmentDeletionBlocker>> _waterProfileDeletionBlockers(
    String id,
  ) async {
    final water = await (database.select(
      database.waterProfiles,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (water == null) throw StateError('Water profile not found');
    final brew =
        await (database.select(database.brews)
              ..where((row) => row.waterProfileId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    var usedInCupping = false;
    // These references live in JSON, so foreign keys cannot protect them.
    // Include completed sessions and retained per-cup selections as well.
    for (final session
        in await database.select(database.cuppingSessions).get()) {
      final draft = CuppingDraft.fromJson(session.draftJson);
      if (draft.waterProfileId == id ||
          draft.cups.any((cup) => cup.waterProfileId == id)) {
        usedInCupping = true;
        break;
      }
    }
    return [
      if (brew != null) EquipmentDeletionBlocker.brews,
      if (usedInCupping) EquipmentDeletionBlocker.cupping,
    ];
  }

  Future<void> deleteUnusedMethod(String id) => database.transaction(() async {
    final blockers = await _methodDeletionBlockers(id);
    if (blockers.isNotEmpty) throw EquipmentInUseException(blockers);
    await _deleteEquipmentImportRecords('method', id);
    await (database.delete(
      database.brewMethods,
    )..where((row) => row.id.equals(id))).go();
  });

  Future<void> deleteUnusedWaterProfile(String id) =>
      database.transaction(() async {
        final blockers = await _waterProfileDeletionBlockers(id);
        if (blockers.isNotEmpty) throw EquipmentInUseException(blockers);
        await _deleteEquipmentImportRecords('water', id);
        await (database.delete(
          database.waterProfiles,
        )..where((row) => row.id.equals(id))).go();
      });

  Future<void> _deleteEquipmentImportRecords(String entity, String id) async {
    // Match coffee/brew deletion: remove provenance so reimport is possible.
    // Only these mappings and their own legacy payloads are removed.
    await (database.delete(database.importRecords)..where(
          (row) => row.localEntity.equals(entity) & row.localId.equals(id),
        ))
        .go();
  }
}
