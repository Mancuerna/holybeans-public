import 'package:holybeans/data/database/app_database.dart';

/// Shared tools, compatibility and distinct brew counts (archived included).
class ToolCatalog {
  ToolCatalog({
    required List<MethodTool> tools,
    required List<ToolMethodLink> links,
    required List<BrewToolSelection> selections,
  }) : byId = {for (final tool in tools) tool.id: tool} {
    for (final tool in tools) {
      canonicalId(tool.id); // Reject cycles and missing merge targets.
    }
    for (final link in links) {
      methodsByTool
          .putIfAbsent(canonicalId(link.toolId), () => {})
          .add(link.methodId);
    }
    final brewsByTool = <String, Set<String>>{};
    for (final selection in selections) {
      brewsByTool
          .putIfAbsent(canonicalId(selection.toolId), () => {})
          .add(selection.brewId);
    }
    useCounts.addAll({
      for (final entry in brewsByTool.entries) entry.key: entry.value.length,
    });
  }

  final Map<String, MethodTool> byId;
  final Map<String, Set<String>> methodsByTool = {};
  final Map<String, int> useCounts = {};

  String canonicalId(String id) {
    final visited = <String>{};
    var current = id;
    while (true) {
      if (!visited.add(current)) throw StateError('Tool merge cycle');
      final tool = byId[current];
      if (tool == null) throw StateError('Tool not found');
      final target = tool.mergedIntoId;
      if (target == null) return current;
      current = target;
    }
  }

  List<MethodTool> visible({bool includeArchived = false}) =>
      [
        for (final tool in byId.values)
          if (tool.mergedIntoId == null &&
              (includeArchived || tool.archivedAtMs == null))
            tool,
      ]..sort((a, b) {
        final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return name == 0 ? a.id.compareTo(b.id) : name;
      });

  List<MethodTool> forMethod(
    String methodId, {
    bool includeArchived = false,
    Iterable<String> retainedIds = const [],
  }) {
    final retained = {for (final id in retainedIds) canonicalId(id)};
    return visible(includeArchived: true)
        .where(
          (tool) =>
              retained.contains(tool.id) ||
              ((methodsByTool[tool.id]?.contains(methodId) ?? false) &&
                  (includeArchived || tool.archivedAtMs == null)),
        )
        .toList();
  }
}
