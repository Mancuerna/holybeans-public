import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

class PistonChart extends StatefulWidget {
  const PistonChart({
    super.key,
    required this.points,
    required this.services,
    required this.speed,
  });
  final List<PistonPoint> points;
  final List<PistonService> services;
  final bool speed;
  @override
  State<PistonChart> createState() => _PistonChartState();
}

class _PistonChartState extends State<PistonChart> {
  int? selected;
  @override
  void didUpdateWidget(PistonChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final locale = regionalLocale.toString();
    final value = NumberFormat('0.000', locale);
    final unit = widget.speed ? 'mm/s' : 'A';
    final point = widget.points.isEmpty
        ? null
        : widget.points[selected ?? widget.points.length - 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          point == null
              ? s.pistonNoRange
              : '${formatRegionalDateTime(DateTime.fromMillisecondsSinceEpoch(point.timeMs), regionalLocale)} · ${value.format(point.raw)} $unit',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (point != null)
          Semantics(
            label: '${s.pistonMedian}: ${value.format(point.value)} $unit',
            child: SizedBox(
              height: 240,
              child: LayoutBuilder(
                builder: (context, box) {
                  void pick(Offset offset) {
                    final fraction =
                        ((offset.dx - 48) / math.max(1, box.maxWidth - 62))
                            .clamp(0.0, 1.0);
                    final first = widget.points.first.timeMs;
                    final last = widget.points.last.timeMs;
                    final target = first + (last - first) * fraction;
                    var best = 0;
                    for (var i = 1; i < widget.points.length; i++) {
                      if ((widget.points[i].timeMs - target).abs() <
                          (widget.points[best].timeMs - target).abs()) {
                        best = i;
                      }
                    }
                    setState(() => selected = best);
                  }

                  return GestureDetector(
                    onTapDown: (d) => pick(d.localPosition),
                    onHorizontalDragUpdate: (d) => pick(d.localPosition),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(box.maxWidth, 240),
                        painter: _PistonPainter(
                          widget.points,
                          widget.services,
                          Theme.of(context).colorScheme,
                          locale,
                          unit,
                          selected,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '● ${s.pistonMeasurements}',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
            Text(
              '━ ${s.pistonMedian}',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            Text(
              '┆ ${s.pistonMaintenance}',
              style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
            ),
          ],
        ),
      ],
    );
  }
}

class _PistonPainter extends CustomPainter {
  _PistonPainter(
    this.points,
    this.services,
    this.colors,
    this.locale,
    this.unit,
    this.selected,
  ) : _pointValues = [
        for (final p in points) (p.timeMs, p.value, p.raw, p.cycle),
      ],
      _serviceTimes = [for (final s in services) s.timeMs];
  final List<PistonPoint> points;
  final List<PistonService> services;
  // Snapshot values before a caller can reuse and update either input list.
  final List<(int, double, double, int)> _pointValues;
  final List<int> _serviceTimes;
  final ColorScheme colors;
  final String locale;
  final String unit;
  final int? selected;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    const top = 15.0;
    final right = size.width - 14;
    final bottom = size.height - 30;
    final minT = points.first.timeMs;
    final maxT = points.last.timeMs;
    final values = points.expand((p) => [p.raw, p.value]);
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final pad = math.max(.04, (maxV - minV) * .15);
    final lo = math.max(0.0, minV - pad);
    final hi = maxV + pad;
    double x(int t) => maxT == minT
        ? (left + right) / 2
        : left + (t - minT) / (maxT - minT) * (right - left);
    double y(double v) => bottom - (v - lo) / (hi - lo) * (bottom - top);
    void label(String text, Offset pos, {bool end = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(end ? pos.dx - painter.width : pos.dx, pos.dy),
      );
      painter.dispose();
    }

    for (var i = 0; i < 4; i++) {
      final v = lo + (hi - lo) * i / 3;
      canvas.drawLine(
        Offset(left, y(v)),
        Offset(right, y(v)),
        Paint()..color = colors.outlineVariant.withValues(alpha: .5),
      );
      label(
        formatDecimal(v, pattern: '0.00', locale: locale),
        Offset(left - 6, y(v) - 6),
        end: true,
      );
    }
    label(unit, Offset.zero);
    final date = DateFormat.MMMd(locale);
    label(
      date.format(DateTime.fromMillisecondsSinceEpoch(minT)),
      Offset(left, bottom + 10),
    );
    if (maxT != minT) {
      label(
        date.format(DateTime.fromMillisecondsSinceEpoch(maxT)),
        Offset(right, bottom + 10),
        end: true,
      );
    }
    for (final s in services.where(
      (s) => s.timeMs >= minT && s.timeMs <= maxT,
    )) {
      for (var yy = top; yy < bottom; yy += 8) {
        canvas.drawLine(
          Offset(x(s.timeMs), yy),
          Offset(x(s.timeMs), math.min(yy + 4, bottom)),
          Paint()
            ..color = colors.tertiary
            ..strokeWidth = 1.5,
        );
      }
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(
        Offset(x(p.timeMs), y(p.raw)),
        2.5,
        Paint()..color = colors.secondary.withValues(alpha: .45),
      );
      if (i > 0 &&
          p.cycle == points[i - 1].cycle &&
          p.timeMs - points[i - 1].timeMs <=
              const Duration(days: 7).inMilliseconds) {
        canvas.drawLine(
          Offset(x(points[i - 1].timeMs), y(points[i - 1].value)),
          Offset(x(p.timeMs), y(p.value)),
          Paint()
            ..color = colors.primary
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        Offset(x(p.timeMs), y(p.value)),
        1.7,
        Paint()..color = colors.primary,
      );
    }
    if (selected != null) {
      final p = points[selected!];
      canvas.drawLine(
        Offset(x(p.timeMs), top),
        Offset(x(p.timeMs), bottom),
        Paint()..color = colors.onSurfaceVariant,
      );
      canvas.drawCircle(
        Offset(x(p.timeMs), y(p.raw)),
        5,
        Paint()..color = colors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PistonPainter old) =>
      !listEquals(old._pointValues, _pointValues) ||
      !listEquals(old._serviceTimes, _serviceTimes) ||
      old.colors != colors ||
      old.locale != locale ||
      old.unit != unit ||
      old.selected != selected;
}
