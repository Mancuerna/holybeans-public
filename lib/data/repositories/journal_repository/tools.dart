part of '../journal_repository.dart';

extension ToolOperations on JournalRepository {
  Future<ToolCatalog> toolCatalog() => tools.toolCatalog();
  Stream<ToolCatalog> watchToolCatalog() => tools.watchToolCatalog();
  Future<List<MethodTool>> methodTools(
    String methodId, {
    bool includeArchived = false,
    Iterable<String> retainedIds = const [],
  }) => tools.methodTools(
    methodId,
    includeArchived: includeArchived,
    retainedIds: retainedIds,
  );
  Future<List<String>> brewToolIds(String brewId) => tools.brewToolIds(brewId);
  Future<String> createTool({
    required String name,
    List<String> methodIds = const [],
  }) => tools.createTool(name: name, methodIds: methodIds);

  /// Retained API for callers creating a new tool from a method.
  Future<String> createMethodTool({
    required String methodId,
    required String name,
  }) => tools.createMethodTool(methodId: methodId, name: name);
  Future<void> updateTool({
    required String id,
    required String name,
    required List<String> methodIds,
  }) => tools.updateTool(id: id, name: name, methodIds: methodIds);
  Future<void> updateMethodTool({required String id, required String name}) =>
      tools.updateMethodTool(id: id, name: name);
  Future<void> associateTool(String toolId, String methodId) =>
      tools.associateTool(toolId, methodId);
  Future<void> dissociateTool(String toolId, String methodId) =>
      tools.dissociateTool(toolId, methodId);
  Future<void> setMethodToolArchived(String id, {required bool archived}) =>
      tools.setMethodToolArchived(id, archived: archived);

  /// Explicitly joins identities. Old selections and import IDs are retained
  /// through redirects, so reimport cannot recreate the merged duplicate.
  Future<void> mergeTools({
    required String sourceId,
    required String targetId,
  }) => tools.mergeTools(sourceId: sourceId, targetId: targetId);
  Future<List<String>> _resolveBrewTools(
    String methodId,
    List<String>? toolIds, {
    required bool keepPrevious,
    Brew? previous,
  }) => tools.resolveBrewTools(
    methodId,
    toolIds,
    keepPrevious: keepPrevious,
    previous: previous,
  );
}
