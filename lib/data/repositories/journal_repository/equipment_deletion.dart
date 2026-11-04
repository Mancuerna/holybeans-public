part of '../journal_repository.dart';

enum EquipmentDeletionBlocker { brews, tools, machine, recipient, cupping }

class EquipmentInUseException implements Exception {
  EquipmentInUseException(Iterable<EquipmentDeletionBlocker> blockers)
    : blockers = List.unmodifiable(blockers);

  final List<EquipmentDeletionBlocker> blockers;
}

extension EquipmentDeletion on JournalRepository {
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
