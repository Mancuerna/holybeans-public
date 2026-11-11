typedef CatalogTool = ({
  String id,
  String name,
  int? archivedAtMs,
  String? mergedIntoId,
});

typedef CatalogLink = ({String toolId, String methodId});

typedef CatalogSelection = ({String toolId, String brewId});
