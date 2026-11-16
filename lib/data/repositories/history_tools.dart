import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';

class HistoryTools {
  HistoryTools(List<MethodTool> tools)
    : catalog = ToolCatalog(
        tools: tools,
        links: const [],
        selections: const [],
      );

  final ToolCatalog catalog;

  List<MethodTool> get options => catalog.visible(includeArchived: true);

  List<Set<String>> groups(List<String> selected) {
    final aliases = <String, Set<String>>{};
    for (final id in catalog.byId.keys) {
      (aliases[catalog.canonicalId(id)] ??= {}).add(id);
    }
    return [
      for (final id in selected)
        aliases[catalog.byId.containsKey(id) ? catalog.canonicalId(id) : id] ??
            {id},
    ];
  }

  Set<String>? matchingBrews(
    List<String> selected,
    List<BrewToolSelection> selections,
  ) {
    if (selected.isEmpty) return null;
    final byBrew = <String, Set<String>>{};
    for (final selection in selections) {
      (byBrew[selection.brewId] ??= {}).add(selection.toolId);
    }
    final required = groups(selected);
    return {
      for (final entry in byBrew.entries)
        if (required.every((ids) => ids.any(entry.value.contains))) entry.key,
    };
  }
}
