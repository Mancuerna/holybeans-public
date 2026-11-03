import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show NumberFormat;

enum WaterPointKind { profile, reference, initial, target, result }

class WaterChartPoint {
  const WaterChartPoint({
    required this.id,
    required this.label,
    required this.water,
    this.kind = WaterPointKind.profile,
  });
  final String id;
  final String label;
  final WaterComposition water;
  final WaterPointKind kind;
  bool get hasCoordinates => water.gh != null && water.kh != null;
}

class WaterChart extends StatefulWidget {
  const WaterChart({super.key, required this.points, this.onPoint});
  final List<WaterChartPoint> points;
  final ValueChanged<WaterChartPoint>? onPoint;

  @override
  State<WaterChart> createState() => _WaterChartState();
}

class _WaterChartState extends State<WaterChart> {
  Set<String> selected = {};

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final points = widget.points.where((p) => p.hasCoordinates).toList();
    final number = NumberFormat('0.##', regionalLocale.toString());
    String summary(WaterChartPoint p) =>
        '${p.label}, GH ${number.format(p.water.gh)}, KH ${number.format(p.water.kh)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.waterChartHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(s.waterNoChartPoints),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, 300);
              final maxValue = points.fold<double>(
                0,
                (max, p) => math.max(max, math.max(p.water.gh!, p.water.kh!)),
              );
              final maximum = math.max(
                20.0,
                (maxValue * 1.12 / 20).ceil() * 20.0,
              );
              final painter = _WaterChartPainter(
                points: points,
                maximum: maximum,
                colors: colors,
                selected: selected,
                ghLabel: s.waterGhAxis,
                khLabel: s.waterKhAxis,
                number: number,
                textScaler: MediaQuery.textScalerOf(context),
              );
              return SizedBox(
                height: size.height,
                child: ClipRect(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: GestureDetector(
                      onTapUp: (tap) {
                        final distances = {
                          for (final point in points)
                            point.id:
                                (painter.position(point, size) -
                                        tap.localPosition)
                                    .distance,
                        };
                        final nearest = distances.values.fold<double>(
                          double.infinity,
                          math.min,
                        );
                        if (nearest > 24) return;
                        setState(
                          () => selected = {
                            for (final p in points)
                              if (distances[p.id]! <= nearest + 1) p.id,
                          },
                        );
                      },
                      child: CustomPaint(
                        key: const ValueKey('water-scatter-chart'),
                        size: size,
                        painter: painter,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (widget.points.any((p) => !p.hasCoordinates))
          Text(s.waterMissingCoordinates),
        for (final point in points.where((p) => selected.contains(p.id)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(point.label),
            subtitle: Text(
              'GH ${number.format(point.water.gh)}    KH ${number.format(point.water.kh)}',
            ),
            trailing: widget.onPoint == null
                ? null
                : const Icon(Icons.chevron_right),
            onTap: widget.onPoint == null ? null : () => widget.onPoint!(point),
          ),
        // These buttons also make every point reachable without precise taps.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final point in points)
              ActionChip(
                key: ValueKey('water-point-${point.id}'),
                avatar: Icon(
                  _pointIcon(point.kind),
                  size: 16,
                  color: _pointColor(colors, point.kind),
                ),
                label: Text(point.label),
                tooltip: summary(point),
                onPressed: () {
                  setState(() => selected = {point.id});
                  widget.onPoint?.call(point);
                },
              ),
          ],
        ),
      ],
    );
  }
}

IconData _pointIcon(WaterPointKind kind) => switch (kind) {
  WaterPointKind.reference => Icons.circle_outlined,
  WaterPointKind.initial => Icons.crop_square,
  WaterPointKind.target => Icons.diamond_outlined,
  _ => Icons.circle,
};

Color _pointColor(ColorScheme colors, WaterPointKind kind) => switch (kind) {
  WaterPointKind.initial => colors.onSurfaceVariant,
  WaterPointKind.reference || WaterPointKind.target => colors.tertiary,
  _ => colors.primary,
};

class _WaterChartPainter extends CustomPainter {
  _WaterChartPainter({
    required this.points,
    required this.maximum,
    required this.colors,
    required this.selected,
    required this.ghLabel,
    required this.khLabel,
    required this.number,
    required this.textScaler,
  });
  final List<WaterChartPoint> points;
  final double maximum;
  final ColorScheme colors;
  final Set<String> selected;
  final String ghLabel;
  final String khLabel;
  final NumberFormat number;
  final TextScaler textScaler;

  Rect plot(Size size) {
    final scale = textScaler.scale(1);
    return Rect.fromLTRB(
      math.min(size.width * .4, 52 * scale),
      30,
      size.width - 16,
      size.height - math.min(size.height * .3, 50 * scale),
    );
  }

  Offset position(WaterChartPoint point, Size size) {
    final rect = plot(size);
    return Offset(
      rect.left + rect.width * point.water.kh! / maximum,
      rect.bottom - rect.height * point.water.gh! / maximum,
    );
  }

  void _text(Canvas canvas, String text, Offset at, {bool centered = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    painter.paint(canvas, centered ? at - Offset(painter.width / 2, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = plot(size);
    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 4; i++) {
      final x = rect.left + rect.width * i / 4;
      final y = rect.bottom - rect.height * i / 4;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      _text(
        canvas,
        number.format(maximum * i / 4),
        Offset(x, rect.bottom + 6),
        centered: true,
      );
      _text(canvas, number.format(maximum * i / 4), Offset(4, y - 7));
    }
    _text(canvas, ghLabel, Offset(rect.left, 5));
    _text(
      canvas,
      khLabel,
      Offset(rect.center.dx, size.height - 20),
      centered: true,
    );
    final initial = points
        .where((p) => p.kind == WaterPointKind.initial)
        .firstOrNull;
    final result = points
        .where((p) => p.kind == WaterPointKind.result)
        .firstOrNull;
    if (initial != null && result != null) {
      final start = position(initial, size);
      final end = position(result, size);
      final line = Paint()
        ..color = colors.primary.withValues(alpha: .5)
        ..strokeWidth = 1.5;
      canvas.drawLine(start, end, line);
      if ((end - start).distance > 14) {
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        for (final offset in [-.45, .45]) {
          canvas.drawLine(
            end,
            end -
                Offset(math.cos(angle + offset), math.sin(angle + offset)) * 10,
            line,
          );
        }
      }
    }
    for (final point in points) {
      final center = position(point, size);
      final paint = Paint()
        ..color = _pointColor(colors, point.kind)
        ..strokeWidth = 2;
      if (selected.contains(point.id)) {
        canvas.drawCircle(
          center,
          11,
          Paint()..color = paint.color.withValues(alpha: .15),
        );
      }
      switch (point.kind) {
        case WaterPointKind.initial:
          canvas.drawRect(
            Rect.fromCenter(center: center, width: 10, height: 10),
            paint..style = PaintingStyle.stroke,
          );
        case WaterPointKind.target:
          final path = Path()
            ..moveTo(center.dx, center.dy - 9)
            ..lineTo(center.dx + 9, center.dy)
            ..lineTo(center.dx, center.dy + 9)
            ..lineTo(center.dx - 9, center.dy)
            ..close();
          canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        case WaterPointKind.reference:
          canvas.drawCircle(center, 7, paint..style = PaintingStyle.stroke);
        case WaterPointKind.profile || WaterPointKind.result:
          canvas.drawCircle(center, 4.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WaterChartPainter oldDelegate) => true;
}
