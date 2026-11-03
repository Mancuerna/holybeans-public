import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// The water a pour plan expects on the scale over time: a rise for each
/// step and a flat wait until the next. [elapsedSeconds] draws a cursor
/// while the plan is followed, and [actual] the weight the scale read.
class PourChart extends StatelessWidget {
  const PourChart({
    super.key,
    required this.plan,
    this.elapsedSeconds,
    this.actual,
    this.height = 180,
  });

  final PourPlan plan;
  final double? elapsedSeconds;
  final ShotCurve? actual;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('pour-chart'),
      height: height,
      width: double.infinity,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _PourPainter(
            plan: plan,
            elapsed: elapsedSeconds,
            actual: actual,
            actualColor: curveSeriesColor(context, CurveSeries.weight),
            line: theme.colorScheme.primary,
            done: theme.colorScheme.tertiary,
            grid: theme.colorScheme.outlineVariant,
            labels: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            format: NumberFormat('0.#', regionalLocale.toString()),
          ),
        ),
      ),
    );
  }
}

class _PourPainter extends CustomPainter {
  _PourPainter({
    required this.plan,
    required this.elapsed,
    required this.actual,
    required this.actualColor,
    required this.line,
    required this.done,
    required this.grid,
    required this.labels,
    required this.format,
  });

  final PourPlan plan;
  final double? elapsed;
  final ShotCurve? actual;
  final Color actualColor;
  final Color line;
  final Color done;
  final Color grid;
  final TextStyle labels;
  final NumberFormat format;

  TextPainter _label(String text) => TextPainter(
    text: TextSpan(text: text, style: labels),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.problem != null) return;
    final measured = actual;
    final end = math.max(
      plan.pouringEndSecond + 15.0,
      (measured?.durationMs ?? 0) / 1000,
    );
    final highest = math.max(
      plan.totalWaterGrams,
      measured?.maxOf(CurveSeries.weight) ?? 0,
    );
    final gramTicks = axisTicks(highest);
    final top = gramTicks.isEmpty ? highest : gramTicks.last;
    final plot = Rect.fromLTRB(36, 8, size.width - 8, size.height - 20);
    double x(double second) => plot.left + plot.width * second / end;
    double y(double grams) => plot.bottom - plot.height * grams / top;

    final faint = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final tick in gramTicks) {
      canvas.drawLine(
        Offset(plot.left, y(tick)),
        Offset(plot.right, y(tick)),
        faint,
      );
      final label = _label(format.format(tick));
      label.paint(
        canvas,
        Offset(plot.left - 5 - label.width, y(tick) - label.height / 2),
      );
    }
    for (final tick in axisTicks(end)) {
      if (tick > end) break;
      final label = _label('${format.format(tick)} s');
      final dx = math.min(x(tick) - label.width / 2, plot.right - label.width);
      label.paint(canvas, Offset(math.max(plot.left - 4, dx), plot.bottom + 4));
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, Paint()..color = grid);

    Path curve(double from, double to) {
      final path = Path()..moveTo(x(from), y(plan.plannedGramsAt(from)));
      for (var second = from; second <= to; second += 0.5) {
        path.lineTo(x(second), y(plan.plannedGramsAt(second)));
      }
      return path;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      curve(0, end),
      stroke..color = line.withValues(alpha: 0.45),
    );
    if (elapsed case final now?) {
      final clamped = now.clamp(0.0, end);
      canvas.drawPath(curve(0, clamped), stroke..color = done);
      canvas.drawLine(
        Offset(x(clamped), plot.top),
        Offset(x(clamped), plot.bottom),
        Paint()
          ..color = labels.color!
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        Offset(x(clamped), y(plan.plannedGramsAt(clamped))),
        5,
        Paint()..color = done,
      );
    }
    if (measured != null && measured.timesMs.length > 1) {
      final path = Path();
      for (var i = 0; i < measured.timesMs.length; i++) {
        final point = Offset(
          x(measured.timesMs[i] / 1000),
          y(measured.weight[i].clamp(0, top)),
        );
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round
          ..color = actualColor,
      );
    }
    for (final step in plan.steps) {
      canvas.drawCircle(
        Offset(
          x(step.startSecond.toDouble()),
          y(step.targetGrams - step.addGrams),
        ),
        3,
        Paint()..color = line,
      );
    }
  }

  @override
  bool shouldRepaint(_PourPainter old) =>
      old.plan != plan ||
      old.elapsed != elapsed ||
      old.actual != actual ||
      old.line != line;
}
