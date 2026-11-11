import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// One series of two brews over time: A solid and B dashed, both in the
/// series' own [color], over round ticks.
class ComparisonPlot extends StatelessWidget {
  const ComparisonPlot({
    super.key,
    required this.color,
    required this.first,
    required this.second,
    required this.minMs,
    required this.maxMs,
    required this.cursorMs,
    required this.locale,
    required this.onChanged,
    required this.label,
  });

  final Color color;
  final List<ComparisonPoint> first;
  final List<ComparisonPoint> second;
  final double minMs;
  final double maxMs;
  final double cursorMs;
  final String locale;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(double x) => onChanged(
          minMs +
              ((x - 44) / (constraints.maxWidth - 52)).clamp(0, 1) *
                  (maxMs - minMs),
        );
        return Semantics(
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => seek(details.localPosition.dx),
            onHorizontalDragStart: (details) => seek(details.localPosition.dx),
            onHorizontalDragUpdate: (details) => seek(details.localPosition.dx),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ComparisonPlotPainter(
                    first: first,
                    second: second,
                    minMs: minMs,
                    maxMs: maxMs,
                    cursorMs: cursorMs,
                    colorA: color,
                    colorB: color,
                    grid: colors.outlineVariant,
                    textColor: colors.onSurfaceVariant,
                    locale: regionalLocale.toString(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ComparisonPlotPainter extends CustomPainter {
  ComparisonPlotPainter({
    required List<ComparisonPoint> first,
    required List<ComparisonPoint> second,
    required this.minMs,
    required this.maxMs,
    required this.cursorMs,
    required this.colorA,
    required this.colorB,
    required this.grid,
    required this.textColor,
    required this.locale,
  }) : first = List.of(first),
       second = List.of(second);

  final List<ComparisonPoint> first;
  final List<ComparisonPoint> second;
  final double minMs;
  final double maxMs;
  final double cursorMs;
  final Color colorA;
  final Color colorB;
  final Color grid;
  final Color textColor;
  final String locale;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(44, 12, size.width - 8, size.height - 30);
    final samples = first.followedBy(second);
    final lowest = samples.fold<double>(
      0,
      (min, point) => math.min(min, point.value),
    );
    final highest = math.max(
      lowest + 1,
      samples.fold<double>(0, (max, point) => math.max(max, point.value)),
    );
    final ticks = lowest < 0 ? rangeTicks(lowest, highest) : axisTicks(highest);
    final minY = lowest < 0 ? lowest : 0.0;
    final maxY = lowest < 0 ? highest : ticks.last;
    final number = NumberFormat('0.#', locale)..turnOffGrouping();
    void label(String text, Offset offset) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: textColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, offset);
      painter.dispose();
    }

    final axis = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final y = area.bottom - area.height * (tick - minY) / (maxY - minY);
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), axis);
      label(number.format(tick), Offset(0, y - 6));
    }
    for (final seconds in rangeTicks(minMs / 1000, maxMs / 1000)) {
      final x =
          area.left + area.width * (seconds * 1000 - minMs) / (maxMs - minMs);
      label(
        formatTimeTick(seconds, number),
        Offset((x - 12).clamp(0, size.width - 30), area.bottom + 8),
      );
    }
    Offset position(({int timeMs, double value}) p) => Offset(
      area.left + area.width * (p.timeMs - minMs) / (maxMs - minMs),
      area.bottom - area.height * (p.value - minY) / (maxY - minY),
    );
    void draw(
      List<({int timeMs, double value})> points,
      Color color,
      bool dashed,
    ) {
      if (points.isEmpty) return;
      final path = Path()
        ..moveTo(position(points.first).dx, position(points.first).dy);
      for (final point in points.skip(1)) {
        final p = position(point);
        path.lineTo(p.dx, p.dy);
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      if (dashed) {
        for (final metric in path.computeMetrics()) {
          for (var distance = 0.0; distance < metric.length; distance += 10) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 6, metric.length),
              ),
              paint,
            );
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (points.length == 1) {
        canvas.drawCircle(position(points.single), 3, Paint()..color = color);
      }
    }

    canvas.save();
    canvas.clipRect(area.inflate(2));
    draw(first, colorA, false);
    draw(second, colorB, true);
    final x = area.left + area.width * (cursorMs - minMs) / (maxMs - minMs);
    canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), axis);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ComparisonPlotPainter old) =>
      !listEquals(old.first, first) ||
      !listEquals(old.second, second) ||
      old.minMs != minMs ||
      old.maxMs != maxMs ||
      old.cursorMs != cursorMs ||
      old.colorA != colorA ||
      old.colorB != colorB ||
      old.grid != grid ||
      old.textColor != textColor ||
      old.locale != locale;
}
