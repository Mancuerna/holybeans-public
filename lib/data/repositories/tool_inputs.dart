import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/tool_inputs.dart';

CatalogTool catalogTool(MethodTool row) => (
  id: row.id,
  name: row.name,
  archivedAtMs: row.archivedAtMs,
  mergedIntoId: row.mergedIntoId,
);

CatalogLink catalogLink(ToolMethodLink row) =>
    (toolId: row.toolId, methodId: row.methodId);

CatalogSelection catalogSelection(BrewToolSelection row) =>
    (toolId: row.toolId, brewId: row.brewId);
