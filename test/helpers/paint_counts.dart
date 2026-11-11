import 'package:flutter/rendering.dart';

/// Counts actual paint calls on [target] while [action] updates its inputs.
Future<int> countPaints(
  RenderObject target,
  Future<void> Function() action,
) async {
  final previous = debugOnProfilePaint;
  var count = 0;
  debugOnProfilePaint = (object) {
    previous?.call(object);
    if (identical(object, target)) count++;
  };
  try {
    await action();
    return count;
  } finally {
    debugOnProfilePaint = previous;
  }
}
