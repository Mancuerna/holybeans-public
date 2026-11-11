import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:intl/intl.dart' show NumberFormat;

class ShotGuideChart extends StatelessWidget {
  const ShotGuideChart({
    super.key,
    required this.reference,
    required this.target,
    required this.unit,
    this.minimumMaximum = 2,
    required this.elapsedMs,
    this.actual,
    this.trace = const [],
  });
  final List<GuidePoint> reference;
  final double? target;
  final String unit;
  final double minimumMaximum;
  final int elapsedMs;
  final double? actual;
  final List<GuidePoint> trace;

  @override
  Widget build(BuildContext context) {
    final painter = _GuidePainter(
      reference,
      target,
      unit,
      minimumMaximum,
      elapsedMs,
      actual,
      trace,
      Theme.of(context).colorScheme,
      NumberFormat('0.#', Localizations.localeOf(context).toString()),
    );
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: _GuideBackdrop(painter))),
          CustomPaint(painter: painter),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(
    this.reference,
    this.target,
    this.unit,
    this.minimumMaximum,
    this.elapsedMs,
    this.actual,
    this.trace,
    this.colors,
    this.number,
  );
  final List<GuidePoint> reference;
  final double? target;
  final String unit;
  final double minimumMaximum;
  final int elapsedMs;
  final double? actual;
  final List<GuidePoint> trace;
  final ColorScheme colors;
  final NumberFormat number;

  late final double maxValue = math.max(
    minimumMaximum,
    math
        .max(
          reference.map((point) => point.value).reduce(math.max),
          math.max(
            trace.fold(0.0, (peak, point) => math.max(peak, point.value)),
            actual ?? 0,
          ),
        )
        .ceilToDouble(),
  );
  late final int maxMs = math.max(
    reference.last.elapsedMs,
    math.max(elapsedMs, trace.isEmpty ? 0 : trace.last.elapsedMs),
  );

  void paintBackground(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(38, 18, size.width - 16, size.height - 30);
    double x(int ms) => area.left + (ms / maxMs).clamp(0, 1) * area.width;
    double y(double value) =>
        area.bottom - (value / maxValue).clamp(0, 1) * area.height;
    void label(String text, Offset at) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 12,
            fontFamily: AppTheme.text,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      try {
        painter.paint(canvas, at);
      } finally {
        painter.dispose();
      }
    }

    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final value = maxValue * i / 4;
      canvas.drawLine(
        Offset(area.left, y(value)),
        Offset(area.right, y(value)),
        grid,
      );
      label(number.format(value), Offset(4, y(value) - 7));
    }
    label(unit, Offset.zero);
    for (var i = 0; i <= 4; i++) {
      final ms = (maxMs * i / 4).round();
      label(
        '${number.format(ms / 1000)} s',
        Offset(x(ms) - 12, area.bottom + 9),
      );
    }
    final path = Path();
    for (var i = 0; i < reference.length; i++) {
      if (i == 0 || reference[i].breakBefore) {
        path.moveTo(x(reference[i].elapsedMs), y(reference[i].value));
      } else {
        path.lineTo(x(reference[i].elapsedMs), y(reference[i].value));
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
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(38, 18, size.width - 16, size.height - 30);
    double x(int ms) => area.left + (ms / maxMs).clamp(0, 1) * area.width;
    double y(double value) =>
        area.bottom - (value / maxValue).clamp(0, 1) * area.height;
    final measured = Path();
    for (var i = 0; i < trace.length; i++) {
      final point = trace[i];
      final position = Offset(x(point.elapsedMs), y(point.value));
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
    if (target case final target?) {
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
      final center = Offset(x(latest.elapsedMs), y(latest.value));
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
      reference != oldDelegate.reference ||
      target != oldDelegate.target ||
      unit != oldDelegate.unit ||
      minimumMaximum != oldDelegate.minimumMaximum ||
      elapsedMs != oldDelegate.elapsedMs ||
      actual != oldDelegate.actual ||
      trace != oldDelegate.trace ||
      colors != oldDelegate.colors ||
      number.locale != oldDelegate.number.locale;
}

class _GuideBackdrop extends CustomPainter {
  _GuideBackdrop(this.frame);
  final _GuidePainter frame;

  @override
  void paint(Canvas canvas, Size size) => frame.paintBackground(canvas, size);

  @override
  bool shouldRepaint(covariant _GuideBackdrop oldDelegate) {
    final old = oldDelegate.frame;
    return !listEquals(frame.reference, old.reference) ||
        frame.maxValue != old.maxValue ||
        frame.maxMs != old.maxMs ||
        frame.unit != old.unit ||
        frame.colors != old.colors ||
        frame.number.locale != old.number.locale;
  }
}
