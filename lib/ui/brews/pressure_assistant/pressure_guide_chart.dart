import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:intl/intl.dart' show NumberFormat;

class PressureGuideChart extends StatelessWidget {
  const PressureGuideChart({
    super.key,
    required this.guide,
    required this.elapsedMs,
    this.actual,
    this.trace = const [],
  });
  final PressureGuide guide;
  final int elapsedMs;
  final double? actual;
  final List<PressureTracePoint> trace;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 250,
    width: double.infinity,
    child: CustomPaint(
      painter: _GuidePainter(
        guide,
        elapsedMs,
        actual,
        trace,
        Theme.of(context).colorScheme,
        NumberFormat('0.#', Localizations.localeOf(context).toString()),
      ),
    ),
  );
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(
    this.guide,
    this.elapsedMs,
    this.actual,
    this.trace,
    this.colors,
    this.number,
  );
  final PressureGuide guide;
  final int elapsedMs;
  final double? actual;
  final List<PressureTracePoint> trace;
  final ColorScheme colors;
  final NumberFormat number;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(38, 18, size.width - 16, size.height - 30);
    final measuredPeak = trace.fold(
      0.0,
      (peak, point) => math.max(peak, point.bar),
    );
    final maxBar = math.max(
      10.0,
      math
          .max(guide.bars.reduce(math.max), math.max(measuredPeak, actual ?? 0))
          .ceilToDouble(),
    );
    final maxMs = math.max(
      guide.endMs,
      math.max(elapsedMs, trace.isEmpty ? 0 : trace.last.elapsedMs),
    );
    double x(int ms) => area.left + (ms / maxMs).clamp(0, 1) * area.width;
    double y(double bar) =>
        area.bottom - (bar / maxBar).clamp(0, 1) * area.height;
    void label(String text, Offset at) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final bar = maxBar * i / 4;
      canvas.drawLine(
        Offset(area.left, y(bar)),
        Offset(area.right, y(bar)),
        grid,
      );
      label(number.format(bar), Offset(4, y(bar) - 7));
    }
    label('bar', Offset.zero);
    for (var i = 0; i <= 4; i++) {
      final ms = (maxMs * i / 4).round();
      label(
        '${number.format(ms / 1000)} s',
        Offset(x(ms) - 12, area.bottom + 9),
      );
    }
    final path = Path();
    for (var i = 0; i < guide.timesMs.length; i++) {
      if (i == 0) {
        path.moveTo(x(guide.timesMs[i]), y(guide.bars[i]));
      } else {
        path.lineTo(x(guide.timesMs[i]), y(guide.bars[i]));
      }
    }
    final referencePaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 12) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 7, metric.length)),
          referencePaint,
        );
      }
    }
    final measured = Path();
    for (var i = 0; i < trace.length; i++) {
      final point = trace[i];
      final position = Offset(x(point.elapsedMs), y(point.bar));
      if (i == 0 || point.breakBefore) {
        measured.moveTo(position.dx, position.dy);
        canvas.drawCircle(position, 2.5, Paint()..color = colors.tertiary);
      } else {
        measured.lineTo(position.dx, position.dy);
      }
    }
    canvas.drawPath(
      measured,
      Paint()
        ..color = colors.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final cursor = x(elapsedMs);
    canvas.drawRect(
      Rect.fromLTRB(
        cursor,
        area.top,
        math.min(area.right, x(elapsedMs + 2000)),
        area.bottom,
      ),
      Paint()..color = colors.primary.withValues(alpha: 0.08),
    );
    canvas.drawLine(
      Offset(cursor, area.top),
      Offset(cursor, area.bottom),
      Paint()
        ..color = colors.onSurface
        ..strokeWidth = 2,
    );
    if (guide.targetAt(elapsedMs) case final target?) {
      canvas.drawCircle(
        Offset(cursor, y(target)),
        8,
        Paint()..color = colors.primary,
      );
      canvas.drawCircle(
        Offset(cursor, y(target)),
        4,
        Paint()..color = colors.onPrimary,
      );
    }
    if (actual != null && trace.isNotEmpty) {
      final latest = trace.last;
      final center = Offset(x(latest.elapsedMs), y(latest.bar));
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy - 9)
          ..lineTo(center.dx + 9, center.dy)
          ..lineTo(center.dx, center.dy + 9)
          ..lineTo(center.dx - 9, center.dy)
          ..close(),
        Paint()..color = colors.tertiary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      guide != oldDelegate.guide ||
      elapsedMs != oldDelegate.elapsedMs ||
      actual != oldDelegate.actual ||
      trace != oldDelegate.trace ||
      colors != oldDelegate.colors ||
      number.locale != oldDelegate.number.locale;
}
