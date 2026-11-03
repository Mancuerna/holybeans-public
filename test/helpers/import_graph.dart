/// Finds cycles among supplied source paths. Parts are one library, not imports.
List<String> importCycles(Map<String, Set<String>> graph) {
  final visited = <String>{};
  final active = <String>[];
  final cycles = <String>{};
  void visit(String node) {
    final at = active.indexOf(node);
    if (at >= 0) {
      final loop = active.sublist(at);
      final first = loop.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      final pivot = loop.indexOf(first);
      cycles.add(
        [...loop.skip(pivot), ...loop.take(pivot), first].join(' -> '),
      );
      return;
    }
    if (!visited.add(node)) return;
    active.add(node);
    for (final target in (graph[node] ?? <String>{}).toList()..sort()) {
      if (graph.containsKey(target)) visit(target);
    }
    active.removeLast();
  }

  for (final node in graph.keys.toList()..sort()) {
    visit(node);
  }
  return cycles.toList()..sort();
}
