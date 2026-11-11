import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/equipment_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:uuid/uuid.dart';

/// Shared tools, compatibility and selections for recorded brews.
class ToolRepository {
  ToolRepository(this.database, this.equipment);
  final AppDatabase database;
  final Uuid _uuid = const Uuid();
  final EquipmentRepository equipment;

  Future<ToolCatalog> toolCatalog() =>
      _readToolCatalog(includeSelections: true);

  Future<ToolCatalog> _readToolCatalog({
    String? methodId,
    bool includeLinks = true,
    bool includeSelections = false,
  }) => database.transaction(() async {
    final tools = await database.select(database.methodTools).get();
    final links = database.select(database.toolMethodLinks);
    if (methodId != null) links.where((row) => row.methodId.equals(methodId));
    return ToolCatalog(
      tools: tools,
      links: includeLinks ? await links.get() : const [],
      selections: includeSelections
          ? await database.select(database.brewToolSelections).get()
          : const [],
    );
  });

  Stream<ToolCatalog> watchToolCatalog() => database
      .customSelect(
        'SELECT 1',
        readsFrom: {
          database.methodTools,
          database.toolMethodLinks,
          database.brewToolSelections,
        },
      )
      .watch()
      .asyncMap((_) => toolCatalog());

  Future<List<MethodTool>> methodTools(
    String methodId, {
    bool includeArchived = false,
    Iterable<String> retainedIds = const [],
  }) async => (await _readToolCatalog(methodId: methodId)).forMethod(
    methodId,
    includeArchived: includeArchived,
    retainedIds: retainedIds,
  );

  Future<List<String>> brewToolIds(String brewId) async {
    final catalog = await _readToolCatalog(includeLinks: false);
    return _selectedToolIds(brewId, catalog);
  }

  Future<List<String>> _selectedToolIds(
    String brewId,
    ToolCatalog catalog,
  ) async {
    final selections = await (database.select(
      database.brewToolSelections,
    )..where((selection) => selection.brewId.equals(brewId))).get();
    return {for (final row in selections) catalog.canonicalId(row.toolId)}
        .toList()
      ..sort();
  }

  Future<String> createTool({
    required String name,
    List<String> methodIds = const [],
  }) => database.transaction(() async {
    for (final id in methodIds.toSet()) {
      await equipment.requireMethod(id);
    }
    final id = _uuid.v4();
    await database
        .into(database.methodTools)
        .insert(
          MethodToolsCompanion.insert(
            id: id,
            name: requireCatalogName(name, 'name'),
          ),
        );
    await _replaceToolMethods(id, methodIds);
    return id;
  });

  /// Retained API for callers creating a new tool from a method.
  Future<String> createMethodTool({
    required String methodId,
    required String name,
  }) => createTool(name: name, methodIds: [methodId]);

  Future<void> updateTool({
    required String id,
    required String name,
    required List<String> methodIds,
  }) => database.transaction(() async {
    final catalog = await _readToolCatalog();
    final canonical = catalog.canonicalId(id);
    for (final methodId in methodIds.toSet()) {
      await equipment.requireMethod(methodId);
    }
    await (database.update(
      database.methodTools,
    )..where((tool) => tool.id.equals(canonical))).write(
      MethodToolsCompanion(name: Value(requireCatalogName(name, 'name'))),
    );
    await _replaceToolMethods(canonical, methodIds);
  });

  Future<void> updateMethodTool({
    required String id,
    required String name,
  }) async {
    final catalog = await _readToolCatalog();
    final canonical = catalog.canonicalId(id);
    await updateTool(
      id: canonical,
      name: name,
      methodIds: catalog.methodsByTool[canonical]?.toList() ?? [],
    );
  }

  Future<void> _replaceToolMethods(
    String toolId,
    Iterable<String> methodIds,
  ) async {
    await (database.delete(
      database.toolMethodLinks,
    )..where((row) => row.toolId.equals(toolId))).go();
    await database.batch(
      (batch) => batch.insertAll(database.toolMethodLinks, [
        for (final methodId in methodIds.toSet())
          ToolMethodLink(toolId: toolId, methodId: methodId),
      ]),
    );
  }

  Future<void> associateTool(String toolId, String methodId) =>
      database.transaction(() async {
        await equipment.requireMethod(methodId);
        final catalog = await _readToolCatalog();
        final canonical = catalog.canonicalId(toolId);
        if (catalog.byId[canonical]!.archivedAtMs != null) {
          throw StateError('Archived tool cannot be associated');
        }
        await database
            .into(database.toolMethodLinks)
            .insert(
              ToolMethodLink(toolId: canonical, methodId: methodId),
              mode: InsertMode.insertOrIgnore,
            );
      });

  Future<void> dissociateTool(String toolId, String methodId) =>
      database.transaction(() async {
        final catalog = await _readToolCatalog();
        final canonical = catalog.canonicalId(toolId);
        await (database.delete(database.toolMethodLinks)..where(
              (row) =>
                  row.toolId.equals(canonical) & row.methodId.equals(methodId),
            ))
            .go();
      });

  Future<void> setMethodToolArchived(String id, {required bool archived}) =>
      database.transaction(() async {
        final canonical = (await _readToolCatalog()).canonicalId(id);
        await (database.update(
          database.methodTools,
        )..where((tool) => tool.id.equals(canonical))).write(
          MethodToolsCompanion(
            archivedAtMs: Value(
              archived ? DateTime.now().toUtc().millisecondsSinceEpoch : null,
            ),
          ),
        );
      });

  /// Explicitly joins identities. Old selections and import IDs are retained
  /// through redirects, so reimport cannot recreate the merged duplicate.
  Future<void> mergeTools({
    required String sourceId,
    required String targetId,
  }) => database.transaction(() async {
    final catalog = await _readToolCatalog();
    final source = catalog.canonicalId(sourceId);
    final target = catalog.canonicalId(targetId);
    if (source == target) {
      throw ArgumentError('Cannot merge a tool into itself');
    }
    if (catalog.byId[target]!.archivedAtMs != null) {
      throw StateError('Merge target is archived');
    }
    final sourceIds = {
      for (final id in catalog.byId.keys)
        if (catalog.canonicalId(id) == source) id,
    };
    final methodIds = {
      ...?catalog.methodsByTool[source],
      ...?catalog.methodsByTool[target],
    };
    await (database.update(database.methodTools)
          ..where((tool) => tool.id.isIn(sourceIds)))
        .write(MethodToolsCompanion(mergedIntoId: Value(target)));
    await (database.delete(
      database.toolMethodLinks,
    )..where((row) => row.toolId.isIn(sourceIds))).go();
    await _replaceToolMethods(target, methodIds);
  });

  Future<List<String>> resolveBrewTools(
    String methodId,
    List<String>? toolIds, {
    required bool keepPrevious,
    Brew? previous,
  }) async {
    if (toolIds != null && toolIds.toSet().length != toolIds.length) {
      throw ArgumentError.value(toolIds, 'methodToolIds', 'IDs must be unique');
    }
    final catalog = await _readToolCatalog(methodId: methodId);
    final previousIds =
        previous != null && (keepPrevious || previous.methodId == methodId)
        ? await _selectedToolIds(previous.id, catalog)
        : const <String>[];
    final selected = toolIds ?? (keepPrevious ? previousIds : const <String>[]);
    final retained = previous?.methodId == methodId
        ? previousIds.toSet()
        : <String>{};
    for (final id in selected) {
      final canonical = catalog.canonicalId(id);
      final tool = catalog.byId[canonical]!;
      if (!retained.contains(canonical) &&
          (tool.archivedAtMs != null ||
              !(catalog.methodsByTool[canonical]?.contains(methodId) ??
                  false))) {
        throw StateError('Tool cannot be selected for this method');
      }
    }
    return selected;
  }
}
