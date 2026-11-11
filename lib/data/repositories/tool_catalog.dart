import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/tool_inputs.dart';
import 'package:holybeans/domain/tool_catalog.dart' as rules;

class ToolCatalog {
  ToolCatalog({
    required List<MethodTool> tools,
    required List<ToolMethodLink> links,
    required List<BrewToolSelection> selections,
  }) : byId = {for (final row in tools) row.id: row},
       _facts = rules.ToolCatalog(
         tools: tools.map(catalogTool).toList(),
         links: links.map(catalogLink).toList(),
         selections: selections.map(catalogSelection).toList(),
       );
  final Map<String, MethodTool> byId;
  final rules.ToolCatalog _facts;
  Map<String, Set<String>> get methodsByTool => _facts.methodsByTool;
  Map<String, int> get useCounts => _facts.useCounts;
  String canonicalId(String id) => _facts.canonicalId(id);
  List<MethodTool> visible({bool includeArchived = false}) => [
    for (final row in _facts.visible(includeArchived: includeArchived))
      byId[row.id]!,
  ];
  List<MethodTool> forMethod(
    String methodId, {
    bool includeArchived = false,
    Iterable<String> retainedIds = const [],
  }) => [
    for (final row in _facts.forMethod(
      methodId,
      includeArchived: includeArchived,
      retainedIds: retainedIds,
    ))
      byId[row.id]!,
  ];
}
