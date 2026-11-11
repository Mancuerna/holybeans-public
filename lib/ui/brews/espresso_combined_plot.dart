import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// Pressure and flow use the left scale; beverage weight uses the right scale.
/// Each series keeps the color it has in the brew details; A is solid and B
/// is dashed so the shots remain distinguishable without color.
class EspressoCombinedPlot extends StatelessWidget {
  const EspressoCombinedPlot({
    super.key,
    required this.timeline,
    required this.cursorMs,
    required this.locale,
    required this.flowCompatible,
    required this.onChanged,
  });

  final ComparisonTimeline timeline;
  final double cursorMs;
  final String locale;
  final bool flowCompatible;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const left = 38.0;
        const right = 38.0;
        void seek(double x) => onChanged(
          timeline.minMs.toDouble() +
              ((x - left) / (constraints.maxWidth - left - right)).clamp(0, 1) *
                  (timeline.maxMs - timeline.minMs),
        );
        return Semantics(
          label:
              '${formatDecimal(cursorMs / 1000, pattern: '0.#', locale: regionalLocale.toString())} s',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (event) => seek(event.localPosition.dx),
            onHorizontalDragStart: (event) => seek(event.localPosition.dx),
            onHorizontalDragUpdate: (event) => seek(event.localPosition.dx),
            child: SizedBox(
              height: 232,
              width: double.infinity,
              child: CustomPaint(
                painter: _CombinedPainter(
                  timeline: timeline,
                  cursorMs: cursorMs,
                  locale: locale,
                  flowCompatible: flowCompatible,
                  pressure: curveSeriesColor(context, CurveSeries.pressure),
                  flow: curveSeriesColor(context, CurveSeries.flow),
                  weight: curveSeriesColor(context, CurveSeries.weight),
                  grid: colors.outlineVariant,
                  text: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CombinedPainter extends CustomPainter {
  const _CombinedPainter({
    required this.timeline,
    required this.cursorMs,
    required this.locale,
    required this.flowCompatible,
    required this.pressure,
    required this.flow,
    required this.weight,
    required this.grid,
    required this.text,
  });

  final ComparisonTimeline timeline;
  final double cursorMs;
  final String locale;
  final bool flowCompatible;
  final Color pressure;
  final Color flow;
  final Color weight;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(38, 12, size.width - 38, size.height - 28);
    final leftSeries = [
      CurveSeries.pressure,
      if (flowCompatible) CurveSeries.flow,
    ];
    final leftPoints = [
      for (final series in leftSeries)
        for (final second in [false, true])
          ...timeline.samples(series, second: second),
    ];
    final weightPoints = [
      for (final second in [false, true])
        ...timeline.samples(CurveSeries.weight, second: second),
    ];
    double rangeMax(List<ComparisonPoint> points) => math.max(
      1,
      points.fold<double>(0, (value, point) => math.max(value, point.value)),
    );
    // Round ticks from zero, like the brew details; a stray negative flow
    // sample is clipped below the axis.
    final leftTicks = axisTicks(rangeMax(leftPoints));
    final rightTicks = axisTicks(rangeMax(weightPoints));
    const leftMin = 0.0;
    const rightMin = 0.0;
    final leftMax = leftTicks.last;
    final rightMax = rightTicks.last;
    final number = NumberFormat('0.#', regionalLocale.toString())
      ..turnOffGrouping();

    void label(String value, Offset at, {bool right = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(color: text, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, right ? Offset(at.dx - painter.width, at.dy) : at);
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final tick in leftTicks) {
      final y = area.bottom - area.height * tick / leftMax;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
      label(number.format(tick), Offset(0, y - 6));
    }
    for (final tick in rightTicks) {
      final y = area.bottom - area.height * tick / rightMax;
      label(number.format(tick), Offset(size.width - 1, y - 6), right: true);
    }
    final spanMs = timeline.maxMs - timeline.minMs;
    for (final seconds in rangeTicks(
      timeline.minMs / 1000,
      timeline.maxMs / 1000,
    )) {
      final x =
          area.left + area.width * (seconds * 1000 - timeline.minMs) / spanMs;
      canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), gridPaint);
      final painter = TextPainter(
        text: TextSpan(
          text: formatTimeTick(seconds, number),
          style: TextStyle(color: text, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(0, size.width - painter.width),
          area.bottom + 7,
        ),
      );
    }

    void draw(CurveSeries series, bool second, Color color) {
      final points = timeline.samples(series, second: second);
      if (points.isEmpty) return;
      final min = series == CurveSeries.weight ? rightMin : leftMin;
      final max = series == CurveSeries.weight ? rightMax : leftMax;
      Offset position(ComparisonPoint p) => Offset(
        area.left +
            area.width *
                (p.timeMs - timeline.minMs) /
                (timeline.maxMs - timeline.minMs),
        area.bottom - area.height * (p.value - min) / (max - min),
      );
      final path = Path()
        ..moveTo(position(points.first).dx, position(points.first).dy);
      for (final point in points.skip(1)) {
        final at = position(point);
        path.lineTo(at.dx, at.dy);
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      if (second) {
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
    for (final series in [
      CurveSeries.weight,
      if (flowCompatible) CurveSeries.flow,
      CurveSeries.pressure,
    ]) {
      final color = switch (series) {
        CurveSeries.pressure => pressure,
        CurveSeries.flow => flow,
        CurveSeries.weight => weight,
      };
      draw(series, true, color);
      draw(series, false, color);
    }
    final x =
        area.left +
        area.width *
            (cursorMs - timeline.minMs) /
            (timeline.maxMs - timeline.minMs);
    canvas.drawLine(
      Offset(x, area.top),
      Offset(x, area.bottom),
      Paint()
        ..color = text
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CombinedPainter oldDelegate) =>
      oldDelegate.timeline != timeline ||
      oldDelegate.cursorMs != cursorMs ||
      oldDelegate.flowCompatible != flowCompatible ||
      oldDelegate.pressure != pressure ||
      oldDelegate.flow != flow ||
      oldDelegate.weight != weight;
}
