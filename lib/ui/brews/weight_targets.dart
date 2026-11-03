import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A labelled planning guide, not a recorded measurement.
class WeightTarget {
  const WeightTarget({
    required this.grams,
    required this.label,
    this.active = false,
  });
  final double grams;
  final String label;
  final bool active;
}

/// Paints all guide levels, keeping nearby labels from overlapping.
void paintWeightTargets(
  Canvas canvas,
  Rect plot,
  List<WeightTarget> targets,
  double Function(double) y,
  TextStyle style,
  Color neutral,
  Color accent,
  Color background, {
  bool drawLines = true,
  bool drawLabels = true,
}) {
  final valid = targets.where((t) => t.grams.isFinite && t.grams > 0).toList();
  for (final target in drawLines ? valid : <WeightTarget>[]) {
    final dy = y(target.grams);
    final paint = Paint()
      ..color = (target.active ? accent : neutral).withValues(
        alpha: target.active ? .8 : .35,
      )
      ..strokeWidth = target.active ? 1.6 : 1;
    for (var dx = plot.left; dx < plot.right; dx += 10) {
      canvas.drawLine(
        Offset(dx, dy),
        Offset(math.min(dx + 6, plot.right), dy),
        paint,
      );
    }
  }
  if (!drawLabels) return;
  // The next target has priority when many pours occupy a short plot.
  valid.sort(
    (a, b) =>
        a.active != b.active ? (a.active ? -1 : 1) : b.grams.compareTo(a.grams),
  );
  final occupied = <Rect>[];
  for (final target in valid) {
    final text = TextPainter(
      text: TextSpan(
        text: target.label,
        style: style.copyWith(
          color: style.color ?? neutral,
          fontWeight: target.active ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, plot.width - 8));
    final dy = y(target.grams);
    final left = plot.left + 4;
    final right = plot.right - text.width - 4;
    final above = math.max(plot.top + 2, dy - text.height - 3);
    final below = math.min(plot.bottom - text.height - 2, dy + 3);
    final candidates = [
      Offset(left, above),
      Offset(left, below),
      Offset(right, above),
      Offset(right, below),
    ];
    Rect? bounds;
    for (final at in candidates) {
      final candidate = (at & text.size).inflate(2);
      if (occupied.any((rect) => rect.overlaps(candidate))) continue;
      bounds = candidate;
      break;
    }
    if (bounds == null) {
      var bestDistance = double.infinity;
      for (var y = plot.top + 2; y <= plot.bottom - text.height - 2; y += 2) {
        for (final x in [left, right]) {
          final at = Offset(x, y);
          final candidate = (at & text.size).inflate(2);
          if (occupied.any((rect) => rect.overlaps(candidate))) continue;
          final distance = (y - above).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bounds = candidate;
          }
        }
      }
    }
    if (bounds == null) continue;
    occupied.add(bounds);
    canvas.drawRect(bounds, Paint()..color = background.withValues(alpha: 1));
    text.paint(canvas, Offset(bounds.left + 2, bounds.top + 2));
  }
}
