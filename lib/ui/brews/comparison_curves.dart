import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/comparison_playback.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' show NumberFormat;

class ComparisonCurves extends StatefulWidget {
  const ComparisonCurves({super.key, required this.a, required this.b});
  final ComparisonCurve? a;
  final ComparisonCurve? b;

  @override
  State<ComparisonCurves> createState() => _ComparisonCurvesState();
}

class _ComparisonCurvesState extends State<ComparisonCurves>
    with SingleTickerProviderStateMixin, ComparisonPlayback {
  CurveSeries selected = CurveSeries.weight;
  bool showA = true;
  bool showB = true;
  final cursor = ValueNotifier(0.0);

  @override
  double get playbackPosition => cursor.value;

  @override
  void updatePlaybackPosition(double value) => cursor.value = value;

  @override
  void didUpdateWidget(ComparisonCurves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.a != oldWidget.a || widget.b != oldWidget.b) {
      pausePlayback();
      cursor.value = 0;
    }
  }

  @override
  void dispose() {
    cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final curves = [widget.a, widget.b];
    final available = CurveSeries.values
        .where(
          (series) =>
              curves.any((curve) => curve?.samples(series).isNotEmpty ?? false),
        )
        .toList();
    if (available.isEmpty) return Text(s.comparisonCurvesMissing);
    final series = available.contains(selected) ? selected : available.first;
    final hasA = widget.a?.samples(series).isNotEmpty ?? false;
    final hasB = widget.b?.samples(series).isNotEmpty ?? false;
    final a = showA && hasA ? widget.a : null;
    final b = showB && hasB ? widget.b : null;
    final split = a != null && b != null && !canOverlayCurves(a, b, series);
    final duration = math
        .max(
          1000,
          curves.whereType<ComparisonCurve>().fold<int>(
            0,
            (time, curve) => math.max(time, curve.curve.durationMs),
          ),
        )
        .toDouble();
    final number = NumberFormat('0.#', regionalLocale.toString())
      ..turnOffGrouping();
    String at(ComparisonCurve? curve, double timeMs) {
      if (curve == null) return s.comparisonMissing;
      final samples = curve.samples(series);
      if (samples.isEmpty ||
          timeMs < samples.first.timeMs ||
          timeMs > samples.last.timeMs) {
        return s.comparisonMissing;
      }
      final closest = samples.reduce(
        (a, b) =>
            (a.timeMs - timeMs).abs() <= (b.timeMs - timeMs).abs() ? a : b,
      );
      return '${number.format(closest.value)} ${curve.unit(series)}';
    }

    final theme = Theme.of(context);
    final colorA = theme.colorScheme.primary;
    final colorB = theme.colorScheme.onSurface;
    Widget plot(ComparisonCurve? first, ComparisonCurve? second) => SizedBox(
      key: ValueKey(
        'comparison-plot-${first != null ? 'a' : 'b'}-${series.name}',
      ),
      height: 240,
      child: RepaintBoundary(
        child: ValueListenableBuilder(
          valueListenable: cursor,
          builder: (_, timeMs, _) => CustomPaint(
            painter: _ComparisonPainter(
              a: first,
              b: second,
              series: series,
              durationMs: duration,
              cursorMs: timeMs,
              colorA: colorA,
              colorB: colorB,
              grid: theme.colorScheme.outlineVariant,
              textColor: theme.colorScheme.onSurfaceVariant,
              locale: regionalLocale.toString(),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in available)
              ChoiceChip(
                key: ValueKey('comparison-series-${item.name}'),
                label: Text(switch (item) {
                  CurveSeries.weight => s.curveWeight,
                  CurveSeries.flow => s.curveFlow,
                  CurveSeries.pressure => s.curvePressure,
                }),
                selected: series == item,
                onSelected: (_) => setState(() => selected = item),
              ),
          ],
        ),
        Wrap(
          spacing: 12,
          children: [
            FilterChip(
              key: const ValueKey('comparison-curve-a'),
              avatar: Icon(Icons.show_chart, color: colorA),
              label: const Text('A ━'),
              selected: showA,
              onSelected: widget.a == null
                  ? null
                  : (value) => setState(() => showA = value),
            ),
            FilterChip(
              key: const ValueKey('comparison-curve-b'),
              avatar: Icon(Icons.show_chart, color: colorB),
              label: const Text('B ┄'),
              selected: showB,
              onSelected: widget.b == null
                  ? null
                  : (value) => setState(() => showB = value),
            ),
          ],
        ),
        if (widget.a == null) Text('A: ${s.comparisonCurvesMissing}'),
        if (widget.b == null) Text('B: ${s.comparisonCurvesMissing}'),
        if (widget.a != null && !hasA) Text('A: ${s.comparisonMissing}'),
        if (widget.b != null && !hasB) Text('B: ${s.comparisonMissing}'),
        Text(s.comparisonCurveTime, style: theme.textTheme.bodySmall),
        if (split) ...[
          const SizedBox(height: 8),
          Text(s.comparisonFlowUnits),
          Text('A (${a.unit(series)})'),
          plot(a, null),
          Text('B (${b.unit(series)})'),
          plot(null, b),
        ] else ...[
          Text(
            (a ?? b ?? curves.whereType<ComparisonCurve>().first).unit(series),
          ),
          plot(a, b),
        ],
        Row(
          children: [
            playbackButton(min: 0, max: duration),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: cursor,
                builder: (_, timeMs, _) => Slider(
                  key: const ValueKey('comparison-curve-time'),
                  value: timeMs.clamp(0, duration),
                  max: duration,
                  label: formatDuration((timeMs / 1000).round()),
                  onChangeStart: (_) => pausePlayback(),
                  onChanged: (value) {
                    pausePlayback();
                    updatePlaybackPosition(value);
                  },
                ),
              ),
            ),
          ],
        ),
        ValueListenableBuilder(
          valueListenable: cursor,
          builder: (_, timeMs, _) => Text(
            '${formatDuration((timeMs / 1000).round())}    '
            'A: ${at(a, timeMs)}    B: ${at(b, timeMs)}',
          ),
        ),
      ],
    );
  }
}

class _ComparisonPainter extends CustomPainter {
  _ComparisonPainter({
    required ComparisonCurve? a,
    required ComparisonCurve? b,
    required this.series,
    required this.durationMs,
    required this.cursorMs,
    required this.colorA,
    required this.colorB,
    required this.grid,
    required this.textColor,
    required this.locale,
  }) : first = a?.samples(series) ?? [],
       second = b?.samples(series) ?? [];

  final List<({int timeMs, double value})> first;
  final List<({int timeMs, double value})> second;
  final CurveSeries series;
  final double durationMs;
  final double cursorMs;
  final Color colorA;
  final Color colorB;
  final Color grid;
  final Color textColor;
  final String locale;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(44, 12, size.width - 8, size.height - 30);
    final samples = [...first, ...second];
    // Isolated spikes, like a knock on the scale, are clipped instead of
    // squashing both brews.
    final range = robustRange([for (final point in samples) point.value]);
    final lowest = math.min(0.0, range.low);
    final highest = math.max(lowest + 1, math.max(0.0, range.high));
    // Round values and clock times, as on the espresso comparison.
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
    for (final seconds in timeTicks(durationMs / 1000)) {
      final x = area.left + area.width * seconds * 1000 / durationMs;
      label(
        formatDuration(seconds.round()),
        Offset((x - 12).clamp(0, size.width - 30), area.bottom + 8),
      );
    }
    Offset position(({int timeMs, double value}) p) => Offset(
      area.left + area.width * p.timeMs / durationMs,
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
    final x = area.left + area.width * cursorMs / durationMs;
    canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), axis);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ComparisonPainter old) =>
      !listEquals(old.first, first) ||
      !listEquals(old.second, second) ||
      old.series != series ||
      old.durationMs != durationMs ||
      old.cursorMs != cursorMs ||
      old.colorA != colorA ||
      old.colorB != colorB ||
      old.grid != grid ||
      old.textColor != textColor ||
      old.locale != locale;
}
