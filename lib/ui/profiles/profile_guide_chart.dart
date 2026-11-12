import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/profiles/profile_numbers.dart';
import 'package:intl/intl.dart' show NumberFormat;

class ProfileGuideChart extends StatelessWidget {
  const ProfileGuideChart({
    super.key,
    required this.profile,
    required this.elapsedMs,
    this.flowTrace = const [],
    this.pressureTrace = const [],
    this.flowActual,
    this.pressureActual,
    this.height = 250,
  });
  final ExtractionProfile profile;
  final int elapsedMs;
  final List<GuidePoint> flowTrace;
  final List<GuidePoint> pressureTrace;
  final double? flowActual;
  final double? pressureActual;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _ProfileGuidePainter(
        this,
        Theme.of(context).colorScheme,
        profileNumber(context),
      ),
    ),
  );
}

class ProfileGuideAxes {
  ProfileGuideAxes(ProfileGuideChart chart, Size size)
    : area = Rect.fromLTRB(38, 24, size.width - 38, size.height - 30),
      flowMaximum = _maximum(
        chart.profile.flow,
        chart.flowTrace,
        chart.flowActual,
        6,
      ),
      pressureMaximum = _maximum(
        chart.profile.pressure,
        chart.pressureTrace,
        chart.pressureActual,
        12,
      ),
      maximumMs = [
        chart.profile.durationMs,
        chart.elapsedMs,
        ...chart.flowTrace.map((p) => p.elapsedMs),
        ...chart.pressureTrace.map((p) => p.elapsedMs),
      ].reduce(math.max);

  final Rect area;
  final double flowMaximum;
  final double pressureMaximum;
  final int maximumMs;

  static double _maximum(
    List<GuidePoint> reference,
    List<GuidePoint> trace,
    double? actual,
    double minimum,
  ) => [
    minimum,
    actual ?? 0,
    ...reference.map((p) => p.value),
    ...trace.map((p) => p.value),
  ].reduce(math.max).ceilToDouble();

  double x(int ms) => area.left + (ms / maximumMs).clamp(0, 1) * area.width;
  double y(double value, {required bool flow}) =>
      area.bottom -
      (value / (flow ? flowMaximum : pressureMaximum)).clamp(0, 1) *
          area.height;
}

class _ProfileGuidePainter extends CustomPainter {
  _ProfileGuidePainter(this.chart, this.colors, this.number);
  final ProfileGuideChart chart;
  final ColorScheme colors;
  final NumberFormat number;

  @override
  void paint(Canvas canvas, Size size) {
    final axes = ProfileGuideAxes(chart, size);
    final area = axes.area;
    void label(String text, Offset at, Color color, {bool right = false}) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: AppTheme.text,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, Offset(right ? at.dx - p.width : at.dx, at.dy));
      p.dispose();
    }

    for (var i = 0; i <= 4; i++) {
      final y = area.bottom - area.height * i / 4;
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        Paint()..color = colors.outlineVariant,
      );
      label(
        number.format(axes.flowMaximum * i / 4),
        Offset(0, y - 6),
        colors.primary,
      );
      label(
        number.format(axes.pressureMaximum * i / 4),
        Offset(size.width, y - 6),
        colors.tertiary,
        right: true,
      );
      final ms = (axes.maximumMs * i / 4).round();
      label(
        '${number.format(ms / 1000)} s',
        Offset(axes.x(ms) - 12, area.bottom + 9),
        colors.onSurfaceVariant,
      );
    }
    label('g/s', Offset.zero, colors.primary);
    label('bar', Offset(size.width, 0), colors.tertiary, right: true);
    final cursor = axes.x(chart.elapsedMs);
    canvas.drawRect(
      Rect.fromLTRB(
        cursor,
        area.top,
        axes.x(chart.elapsedMs + 2000),
        area.bottom,
      ),
      Paint()..color = colors.onSurface.withValues(alpha: .05),
    );
    canvas.drawLine(
      Offset(cursor, area.top),
      Offset(cursor, area.bottom),
      Paint()
        ..color = colors.onSurface
        ..strokeWidth = 1.5,
    );
    for (final flow in [true, false]) {
      final color = flow ? colors.primary : colors.tertiary;
      final reference = flow ? chart.profile.flow : chart.profile.pressure;
      final trace = flow ? chart.flowTrace : chart.pressureTrace;
      Offset position(GuidePoint p) =>
          Offset(axes.x(p.elapsedMs), axes.y(p.value, flow: flow));
      Path path(List<GuidePoint> points) {
        final result = Path();
        for (var i = 0; i < points.length; i++) {
          final at = position(points[i]);
          if (i == 0 || points[i].breakBefore) {
            result.moveTo(at.dx, at.dy);
          } else {
            result.lineTo(at.dx, at.dy);
          }
        }
        return result;
      }

      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final metric in path(reference).computeMetrics()) {
        for (var start = 0.0; start < metric.length; start += 12) {
          canvas.drawPath(
            metric.extractPath(start, math.min(start + 7, metric.length)),
            pen,
          );
        }
      }
      canvas.drawPath(path(trace), pen..strokeWidth = 3);
      for (var i = 0; i < trace.length; i++) {
        if (i == 0 || trace[i].breakBefore) {
          canvas.drawCircle(position(trace[i]), 2.5, Paint()..color = color);
        }
      }
      final target = chart.profile.targetAt(reference, chart.elapsedMs);
      if (target != null) {
        final at = Offset(cursor, axes.y(target, flow: flow));
        canvas.drawCircle(at, 6, Paint()..color = colors.surface);
        canvas.drawCircle(
          at,
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      final actual = flow ? chart.flowActual : chart.pressureActual;
      if (actual != null && trace.isNotEmpty) {
        final at = position(trace.last);
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy - 7)
            ..lineTo(at.dx + 7, at.dy)
            ..lineTo(at.dx, at.dy + 7)
            ..lineTo(at.dx - 7, at.dy)
            ..close(),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ProfileGuidePainter oldDelegate) =>
      chart.profile != oldDelegate.chart.profile ||
      chart.elapsedMs != oldDelegate.chart.elapsedMs ||
      chart.flowTrace != oldDelegate.chart.flowTrace ||
      chart.pressureTrace != oldDelegate.chart.pressureTrace ||
      chart.flowActual != oldDelegate.chart.flowActual ||
      chart.pressureActual != oldDelegate.chart.pressureActual ||
      colors != oldDelegate.colors ||
      number.locale != oldDelegate.number.locale;
}
