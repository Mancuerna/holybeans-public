import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One bar: what it is called, its value and the text read for it.
typedef StatsBar = ({String label, double value, String readout});

/// Vertical bars with their labels underneath, as many labels as fit, and
/// each value on top when [valueFormat] is given. Tapping a bar shows its
/// readout above the chart; screen readers hear [summary] and every readout.
class StatsBarChart extends StatefulWidget {
  const StatsBarChart({
    super.key,
    required this.bars,
    required this.summary,
    this.height = 140,
    this.maxValue,
    this.valueFormat,
    this.marked = const {},
  });

  final List<StatsBar> bars;

  /// Bars drawn in green over a soft band, e.g. the times of the best
  /// shots; the rest stay grey.
  final Set<int> marked;
  final String summary;
  final double height;

  /// The top of the scale; the highest bar when not given.
  final double? maxValue;

  /// Writes each bar's value over it, where there is room: for averages,
  /// whose bars differ too little to read by height alone.
  final String Function(double value)? valueFormat;

  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int? selected;

  @override
  void didUpdateWidget(StatsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected != null && selected! >= widget.bars.length) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bars = widget.bars;
    final top =
        widget.maxValue ??
        bars.fold<double>(0, (max, bar) => math.max(max, bar.value));
    final label = theme.textTheme.labelSmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final picked = selected;
    final scaler = MediaQuery.textScalerOf(context);
    final format = widget.valueFormat;
    return Semantics(
      label: [widget.summary, for (final bar in bars) bar.readout].join('. '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20,
            child: Text(
              picked == null ? '' : bars[picked].readout,
              key: const ValueKey('stats-chart-readout'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final slot = bars.isEmpty ? width : width / bars.length;
              void pick(Offset position) {
                if (bars.isEmpty) return;
                final index = (position.dx / slot).floor().clamp(
                  0,
                  bars.length - 1,
                );
                setState(() => selected = selected == index ? null : index);
              }

              return GestureDetector(
                onTapUp: (details) => pick(details.localPosition),
                child: CustomPaint(
                  size: Size(width, widget.height),
                  painter: _BarsPainter(
                    values: [for (final bar in bars) bar.value],
                    top: top,
                    color: colors.onSurfaceVariant,
                    highlight: colors.primary,
                    track: colors.surfaceContainerHighest,
                    selected: picked,
                    marked: widget.marked,
                    markColor: colors.tertiary,
                    markBand: colors.tertiaryContainer,
                    valueLabels: format == null
                        ? null
                        : [for (final bar in bars) format(bar.value)],
                    textStyle: label.copyWith(color: colors.onSurface),
                    textScaler: scaler,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              // Every nth label, so they never run into each other.
              final widest = bars.fold<double>(0, (widest, bar) {
                final painter = TextPainter(
                  text: TextSpan(text: bar.label, style: label),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                )..layout();
                return math.max(widest, painter.width);
              });
              final fit = math.max(
                1,
                (constraints.maxWidth / (widest + 12)).floor(),
              );
              final every = (bars.length / fit).ceil().clamp(1, 1 << 20);
              return Row(
                children: [
                  for (final (index, bar) in bars.indexed)
                    Expanded(
                      child: Text(
                        index % every == 0 ? bar.label : '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: TextAlign.center,
                        style: label,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.top,
    required this.color,
    required this.highlight,
    required this.track,
    required this.selected,
    required this.valueLabels,
    required this.textStyle,
    required this.textScaler,
    this.marked = const {},
    this.markColor,
    this.markBand,
  });

  final List<double> values;
  final double top;
  final Color color;
  final Color highlight;
  final Color track;
  final int? selected;
  final Set<int> marked;
  final Color? markColor;
  final Color? markBand;
  final List<String>? valueLabels;
  final TextStyle textStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    if (values.isEmpty || top <= 0) return;
    final slot = size.width / values.length;
    final barWidth = math.max(2.0, math.min(28.0, slot * 0.7));
    if (marked.isNotEmpty && markBand != null) {
      final first = marked.reduce(math.min);
      final last = marked.reduce(math.max);
      canvas.drawRect(
        Rect.fromLTRB(first * slot, 0, (last + 1) * slot, size.height),
        Paint()..color = markBand!,
      );
    }
    final texts = [
      for (final text in valueLabels ?? const <String>[])
        TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(),
    ];
    // Room over the highest bar for its value.
    final headroom = texts.isEmpty ? 0.0 : texts.first.height + 2;
    final room = size.height - headroom;
    for (final (index, value) in values.indexed) {
      if (value <= 0) continue;
      final height = room * (value / top).clamp(0.0, 1.0);
      final left = index * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()
          ..color = index == selected
              ? highlight
              : marked.contains(index) && markColor != null
              ? markColor!
              : color,
      );
      if (index < texts.length && texts[index].width <= slot) {
        final text = texts[index];
        text.paint(
          canvas,
          Offset(
            index * slot + (slot - text.width) / 2,
            size.height - height - text.height - 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.top != top ||
      old.selected != selected ||
      old.color != color ||
      old.marked.join() != marked.join() ||
      old.valueLabels?.join() != valueLabels?.join() ||
      old.textScaler != textScaler;
}

/// One point of a [StatsScatter].
typedef StatsPoint = ({double x, double y, String readout});

/// Points over two axes, with the axes' ends labelled. Tapping near a point
/// shows its readout; screen readers hear [summary] and every readout.
class StatsScatter extends StatefulWidget {
  const StatsScatter({
    super.key,
    required this.points,
    required this.summary,
    required this.xLabel,
    required this.yLabel,
    required this.xFormat,
    required this.yFormat,
    this.yMin = 0,
    this.yMax = 10,
    this.height = 200,
  });

  final List<StatsPoint> points;
  final String summary;
  final String xLabel;
  final String yLabel;
  final String Function(double value) xFormat;
  final String Function(double value) yFormat;
  final double yMin;
  final double yMax;
  final double height;

  @override
  State<StatsScatter> createState() => _StatsScatterState();
}

class _StatsScatterState extends State<StatsScatter> {
  int? selected;

  static const _left = 28.0;
  static const _bottom = 18.0;

  @override
  void didUpdateWidget(StatsScatter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected != null && selected! >= widget.points.length) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final points = widget.points;
    final xs = [for (final point in points) point.x];
    final xMin = xs.isEmpty ? 0.0 : xs.reduce(math.min);
    final xMax = xs.isEmpty ? 1.0 : xs.reduce(math.max);
    // A little room on both sides, so no point sits on the frame.
    final pad = xMax == xMin ? math.max(xMax * 0.2, 0.1) : (xMax - xMin) * 0.08;
    final low = math.max(0.0, xMin - pad);
    final high = xMax + pad;
    final picked = selected;
    final label = theme.textTheme.labelSmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Semantics(
      label: [
        widget.summary,
        for (final point in points) point.readout,
      ].join('. '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20,
            child: Text(
              picked == null ? '' : points[picked].readout,
              key: const ValueKey('stats-scatter-readout'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          Text(widget.yLabel, style: label),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              final plot = Rect.fromLTRB(
                _left,
                6,
                size.width - 8,
                size.height - _bottom,
              );
              Offset at(StatsPoint point) => Offset(
                plot.left + plot.width * (point.x - low) / (high - low),
                plot.bottom -
                    plot.height *
                        ((point.y - widget.yMin) / (widget.yMax - widget.yMin))
                            .clamp(0.0, 1.0),
              );
              void pick(Offset position) {
                int? nearest;
                var best = 28.0 * 28.0;
                for (final (index, point) in points.indexed) {
                  final distance = (at(point) - position).distanceSquared;
                  if (distance < best) {
                    best = distance;
                    nearest = index;
                  }
                }
                setState(() => selected = nearest == selected ? null : nearest);
              }

              return GestureDetector(
                onTapUp: (details) => pick(details.localPosition),
                child: CustomPaint(
                  size: size,
                  painter: _ScatterPainter(
                    plot: plot,
                    points: [for (final point in points) at(point)],
                    selected: picked,
                    color: colors.onSurfaceVariant,
                    highlight: colors.primary,
                    grid: colors.outlineVariant,
                    labelStyle: label,
                    textScaler: MediaQuery.textScalerOf(context),
                    yLabels: [
                      for (final value in [widget.yMin, widget.yMax])
                        (
                          widget.yFormat(value),
                          plot.bottom -
                              plot.height *
                                  (value - widget.yMin) /
                                  (widget.yMax - widget.yMin),
                        ),
                    ],
                    xLabels: [
                      (widget.xFormat(low), plot.left),
                      (widget.xFormat(high), plot.right),
                    ],
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(widget.xLabel, style: label),
          ),
        ],
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.plot,
    required this.points,
    required this.selected,
    required this.color,
    required this.highlight,
    required this.grid,
    required this.labelStyle,
    required this.textScaler,
    required this.yLabels,
    required this.xLabels,
  });

  final Rect plot;
  final List<Offset> points;
  final int? selected;
  final Color color;
  final Color highlight;
  final Color grid;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final List<(String, double)> yLabels;
  final List<(String, double)> xLabels;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(text: text, style: labelStyle),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas
      ..drawLine(plot.bottomLeft, plot.bottomRight, line)
      ..drawLine(plot.bottomLeft, plot.topLeft, line);
    final faint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var step = 1; step < 4; step++) {
      final dy = plot.bottom - plot.height * step / 4;
      canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), faint);
    }
    for (final (text, dy) in yLabels) {
      final painter = _text(text);
      painter.paint(
        canvas,
        Offset(plot.left - 4 - painter.width, dy - painter.height / 2),
      );
    }
    for (final (index, (text, dx)) in xLabels.indexed) {
      final painter = _text(text);
      painter.paint(
        canvas,
        Offset(index == 0 ? dx : dx - painter.width, plot.bottom + 3),
      );
    }
    for (final (index, point) in points.indexed) {
      final chosen = index == selected;
      canvas.drawCircle(
        point,
        chosen ? 7 : 5,
        Paint()..color = (chosen ? highlight : color).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.plot != plot ||
      old.textScaler != textScaler;
}
