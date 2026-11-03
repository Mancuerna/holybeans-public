part of '../journal_repository.dart';

extension ToolOperations on JournalRepository {
  Future<ToolCatalog> toolCatalog() => database.transaction(
    () async => ToolCatalog(
      tools: await database.select(database.methodTools).get(),
      links: await database.select(database.toolMethodLinks).get(),
      selections: await database.select(database.brewToolSelections).get(),
    ),
  );

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
  }) async => (await toolCatalog()).forMethod(
    methodId,
    includeArchived: includeArchived,
    retainedIds: retainedIds,
  );

  Future<List<String>> brewToolIds(String brewId) async {
    final catalog = await toolCatalog();
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
      await _requireMethod(id);
    }
    final id = _uuid.v4();
    await database
        .into(database.methodTools)
        .insert(
          MethodToolsCompanion.insert(
            id: id,
            name: _requireCatalogName(name, 'name'),
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
    final catalog = await toolCatalog();
    final canonical = catalog.canonicalId(id);
    for (final methodId in methodIds.toSet()) {
      await _requireMethod(methodId);
    }
    await (database.update(
      database.methodTools,
    )..where((tool) => tool.id.equals(canonical))).write(
      MethodToolsCompanion(name: Value(_requireCatalogName(name, 'name'))),
    );
    await _replaceToolMethods(canonical, methodIds);
  });

  Future<void> updateMethodTool({
    required String id,
    required String name,
  }) async {
    final catalog = await toolCatalog();
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
        await _requireMethod(methodId);
        final catalog = await toolCatalog();
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
        final catalog = await toolCatalog();
        final canonical = catalog.canonicalId(toolId);
        await (database.delete(database.toolMethodLinks)..where(
              (row) =>
                  row.toolId.equals(canonical) & row.methodId.equals(methodId),
            ))
            .go();
      });

  Future<void> setMethodToolArchived(String id, {required bool archived}) =>
      database.transaction(() async {
        final canonical = (await toolCatalog()).canonicalId(id);
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
    final catalog = await toolCatalog();
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

  Future<void> _validateMethodTools(
    String methodId,
    List<String> toolIds, {
    Brew? previous,
  }) async {
    if (toolIds.toSet().length != toolIds.length) {
      throw ArgumentError.value(toolIds, 'methodToolIds', 'IDs must be unique');
    }
    final catalog = await toolCatalog();
    final retained = previous?.methodId == methodId
        ? (await brewToolIds(previous!.id)).toSet()
        : <String>{};
    for (final id in toolIds) {
      final canonical = catalog.canonicalId(id);
      final tool = catalog.byId[canonical]!;
      if (!retained.contains(canonical) &&
          (tool.archivedAtMs != null ||
              !(catalog.methodsByTool[canonical]?.contains(methodId) ??
                  false))) {
        throw StateError('Tool cannot be selected for this method');
      }
    }
  }
}
