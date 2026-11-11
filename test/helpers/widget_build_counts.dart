import 'package:flutter/widgets.dart';

/// Counts rebuilds of selected elements while [action] drives the widget tree.
Future<Map<String, int>> countWidgetRebuilds(
  Map<String, Element> elements,
  Future<void> Function() action,
) async {
  final previous = debugOnRebuildDirtyWidget;
  final names = {for (final entry in elements.entries) entry.value: entry.key};
  final counts = {for (final name in elements.keys) name: 0};
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    final name = names[element];
    if (name != null) counts[name] = counts[name]! + 1;
  };
  try {
    await action();
    return counts;
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
}
