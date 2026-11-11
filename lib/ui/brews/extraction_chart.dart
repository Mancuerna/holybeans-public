import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/domain/axis_ticks.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/curve_legend_button.dart';
import 'package:holybeans/ui/brews/curve_view_model.dart';
import 'package:holybeans/ui/brews/extraction_readout.dart';
import 'package:holybeans/ui/brews/weight_targets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Weight in ink, flow in the accent, pressure in blue: told apart by
/// lightness as well as hue.
Color curveSeriesColor(BuildContext context, CurveSeries series) {
  final colors = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (series) {
    CurveSeries.weight => colors.onSurface,
    CurveSeries.flow => colors.primary,
    CurveSeries.pressure =>
      dark ? const Color(0xFF8FB8D8) : const Color(0xFF2F5F80),
  };
}

String curveSeriesLabel(AppLocalizations s, CurveSeries series) =>
    switch (series) {
      CurveSeries.weight => s.curveWeight,
      CurveSeries.flow => s.curveFlow,
      CurveSeries.pressure => s.curvePressure,
    };

/// A brew's recorded pressure and weight, with lightly filtered flow; a
/// scale's curve has no pressure. Pressure and flow share the left axis
/// (bar · ml/s), the weight has its own on the right, and time runs along
/// the bottom. Touching or dragging reads the values at that moment, the
/// chips show or hide series and the play button replays the brew from the
/// cursor and pauses it. [compact] draws only the lines, for small
/// previews.
class ExtractionChart extends StatefulWidget {
  const ExtractionChart({
    super.key,
    required this.curve,
    this.compact = false,
    this.interactive = true,
    this.height,
    this.flowUnit = 'ml/s',
    this.live = false,
    this.action,
    this.replayable = true,
    this.showReadout = true,
    this.firstDripMs,
    this.showFlowStatistics = true,
    this.targetWeightGrams,
    this.weightTargets = const [],
  });

  final bool showFlowStatistics;
  final double? targetWeightGrams;
  final List<WeightTarget> weightTargets;

  final ShotCurve curve;
  final bool compact;
  final bool interactive;
  final double? height;

  /// Whether the curve is still being recorded: it grows as readings come
  /// and there is nothing to replay yet.
  final bool live;

  /// A button beside the line legend, such as the brew timer's start/stop.
  final Widget? action;

  /// Whether the readout offers replaying the shot; the brew form, which
  /// has its own timer button there, leaves it out to avoid two players.
  final bool replayable;

  /// The live filter form has its own progress below the plot.
  final bool showReadout;

  /// A machine measures flow in ml/s, a scale in g/s.
  final String flowUnit;

  /// Recorded first drip, otherwise statistics estimate it from cup weight.
  final int? firstDripMs;

  @override
  State<ExtractionChart> createState() => _ExtractionChartState();
}

class _ExtractionChartState extends State<ExtractionChart>
    with SingleTickerProviderStateMixin {
  late final visible = {...widget.curve.series};

  final model = CurveViewModel();

  @override
  void initState() {
    super.initState();
    model.update(
      widget.curve,
      firstDripMs: widget.firstDripMs,
      live: widget.live,
    );
    model.addListener(_prepared);
  }

  void _prepared() => setState(() {});

  @override
  void didUpdateWidget(ExtractionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curve != widget.curve) {
      final added = widget.curve.series.toSet().difference(
        oldWidget.curve.series.toSet(),
      );
      visible.addAll(added);
      visible.removeWhere((s) => !widget.curve.series.contains(s));
    }
    if (oldWidget.curve != widget.curve ||
        oldWidget.firstDripMs != widget.firstDripMs ||
        oldWidget.live != widget.live) {
      model.update(
        widget.curve,
        firstDripMs: widget.firstDripMs,
        live: widget.live,
      );
    }
  }

  /// Time under the finger or the replay, in milliseconds; null shows the
  /// whole shot with its final values.
  int? cursorMs;
  late final AnimationController replay = AnimationController(vsync: this)
    ..addListener(() {
      setState(
        () => cursorMs = (replay.value * widget.curve.durationMs).round(),
      );
    })
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => cursorMs = null);
      }
    });

  @override
  void dispose() {
    model.removeListener(_prepared);
    model.dispose();
    replay.dispose();
    super.dispose();
  }

  /// Plays from the cursor, or from the start when there is none, and
  /// pauses where it is when already playing.
  void _togglePlay() {
    if (replay.isAnimating) {
      setState(replay.stop);
      return;
    }
    final duration = widget.curve.durationMs;
    final ms = cursorMs;
    final from = ms != null && ms < duration ? ms / duration : 0.0;
    // Twice real time: long enough to follow, short enough to wait for.
    replay
      ..duration = Duration(milliseconds: duration ~/ 2)
      ..forward(from: from);
  }

  void _seek(Offset position, Rect plot) {
    if (replay.isAnimating) replay.stop();
    final fraction = ((position.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    setState(() => cursorMs = (fraction * widget.curve.durationMs).round());
  }

  Widget _controls(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (!widget.interactive) {
      return Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final series in widget.curve.series)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.horizontal_rule,
                  size: 16,
                  color: curveSeriesColor(context, series),
                ),
                const SizedBox(width: 4),
                Text(
                  curveSeriesLabel(s, series),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
        ],
      );
    }
    final seriesControls = Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final series in widget.curve.series)
          CurveLegendButton(
            key: ValueKey('curve-series-${series.name}'),
            label: curveSeriesLabel(s, series),
            color: curveSeriesColor(context, series),
            selected: visible.contains(series),
            onPressed: () => setState(() {
              visible.contains(series)
                  ? visible.remove(series)
                  : visible.add(series);
            }),
          ),
      ],
    );
    final action =
        widget.action ??
        (!widget.live && widget.replayable
            ? IconButton(
                key: const ValueKey('curve-replay'),
                tooltip: replay.isAnimating ? s.curvePause : s.curveReplay,
                onPressed: widget.curve.durationMs > 0 ? _togglePlay : null,
                icon: Icon(
                  replay.isAnimating
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              )
            : null);
    if (action == null) return seriesControls;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: seriesControls),
        const SizedBox(width: 8),
        SizedBox(height: 48, child: action),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prepared = model.value;
    if (prepared == null) {
      return SizedBox(
        height: widget.height ?? (widget.compact ? 72 : 220),
        child: Center(
          child: model.error == null
              ? const CircularProgressIndicator(
                  key: ValueKey('curve-preparing'),
                )
              : Text(s.curveProcessingFailed),
        ),
      );
    }
    final curve = prepared.recorded;
    final shown = prepared.shown;
    final number = NumberFormat('0.0', regionalLocale.toString());
    final drawn = widget.compact
        ? {...curve.series}
        : visible.intersection(curve.series.toSet());
    final height = widget.height ?? (widget.compact ? 72 : 220);
    final painter = _ChartPainter(
      curve: shown,
      display: prepared.display,
      peaks: prepared.peaks,
      recorded: curve,
      visible: drawn,
      tickFormat: NumberFormat('0.#', regionalLocale.toString()),
      colors: {
        for (final series in CurveSeries.values)
          series: curveSeriesColor(context, series),
      },
      gridColor: theme.colorScheme.outlineVariant,
      labelStyle: theme.textTheme.labelSmall!.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      cursorMs: widget.compact ? null : cursorMs,
      compact: widget.compact,
      flowUnit: widget.flowUnit,
      targetWeightGrams: widget.targetWeightGrams,
      weightTargets: widget.weightTargets,
      targetAccent: theme.colorScheme.primary,
      background: theme.colorScheme.surface,
    );
    final chart = SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(child: CustomPaint(painter: painter)),
    );
    final duration = number.format(curve.durationMs / 1000);
    // The peak: a filter brew's last weight drops when the brewer is lifted.
    final finalWeight = number.format(
      curve.weight.isEmpty ? 0 : curve.maxOf(CurveSeries.weight),
    );
    final summary = curve.series.contains(CurveSeries.pressure)
        ? s.curveSummary(
            duration,
            number.format(curve.maxOf(CurveSeries.pressure)),
            finalWeight,
          )
        : s.weightCurveSummary(duration, finalWeight);
    if (widget.compact) {
      return Semantics(label: summary, excludeSemantics: true, child: chart);
    }
    return Semantics(
      label:
          '${s.extractionCurve}. $summary${drawn.contains(CurveSeries.weight) && widget.weightTargets.isNotEmpty ? '. ${widget.weightTargets.map((t) => t.label).join(', ')}' : ''}',
      container: true,
      child: Column(
        key: const ValueKey('extraction-chart'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(context),
          LayoutBuilder(
            builder: (context, constraints) {
              if (!widget.showReadout || !widget.interactive) {
                return ExcludeSemantics(child: chart);
              }
              final plot = _ChartPainter.plotRect(
                Size(constraints.maxWidth, height),
                visible: drawn,
                compact: false,
              );
              return GestureDetector(
                onTapDown: (details) => _seek(details.localPosition, plot),
                onHorizontalDragUpdate: (details) =>
                    _seek(details.localPosition, plot),
                onHorizontalDragEnd: (_) => setState(() => cursorMs = null),
                onTapUp: (_) {},
                child: ExcludeSemantics(child: chart),
              );
            },
          ),
          if (widget.showReadout) ...[
            const SizedBox(height: 8),
            ExtractionReadout(
              curve: curve,
              visible: drawn,
              flowUnit: widget.flowUnit,
              cursorMs: cursorMs,
              flowStats: prepared.flowStats,
              peaks: prepared.peaks,
              showFlowStatistics: widget.showFlowStatistics,
              showTotals: widget.live,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.curve,
    required this.display,
    required this.peaks,
    required this.recorded,
    required this.visible,
    required this.tickFormat,
    required this.colors,
    required this.gridColor,
    required this.labelStyle,
    required this.cursorMs,
    required this.compact,
    required this.flowUnit,
    required this.targetWeightGrams,
    required this.weightTargets,
    required this.targetAccent,
    required this.background,
  }) : _targetValues = [
         for (final target in weightTargets)
           (target.grams, target.label, target.active),
       ];

  final double? targetWeightGrams;
  final List<WeightTarget> weightTargets;
  final List<(double, String, bool)> _targetValues;

  final ShotCurve curve;
  final ShotCurve recorded;
  final ShotCurve display;
  final Map<CurveSeries, double> peaks;
  final Set<CurveSeries> visible;
  final NumberFormat tickFormat;
  final Map<CurveSeries, Color> colors;
  final Color gridColor;
  final TextStyle labelStyle;
  final int? cursorMs;
  final bool compact;
  final String flowUnit;
  final Color targetAccent;
  final Color background;

  static bool _isLiquid(CurveSeries series) => series != CurveSeries.weight;

  /// Where the lines go inside [size], leaving room for the axes in use.
  static Rect plotRect(
    Size size, {
    required Set<CurveSeries> visible,
    required bool compact,
  }) {
    if (compact) return Rect.fromLTRB(2, 2, size.width - 2, size.height - 2);
    final left = visible.any(_isLiquid) ? 32.0 : 8.0;
    final right = visible.contains(CurveSeries.weight) ? 32.0 : 8.0;
    return Rect.fromLTRB(left, 18, size.width - right, size.height - 20);
  }

  /// Top of the left axis (pressure and flow) or of the right one (weight).
  double _top(bool liquid) {
    final max = [
      if (!liquid && visible.contains(CurveSeries.weight))
        targetWeightGrams ?? 0,
      if (!liquid && visible.contains(CurveSeries.weight))
        for (final target in weightTargets)
          if (target.grams.isFinite && target.grams > 0) target.grams,
      for (final series in CurveSeries.values)
        if (visible.contains(series) && _isLiquid(series) == liquid)
          // A knock on the scale would squash the brew under its spike;
          // pressure keeps its real peak, which is labelled.
          peaks[series] ?? 0,
    ].fold(0.0, math.max);
    final ticks = axisTicks(max);
    return ticks.isEmpty ? 1 : ticks.last;
  }

  TextPainter _label(String text, Color color) => TextPainter(
    text: TextSpan(
      text: text,
      style: labelStyle.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintLabel(Canvas canvas, String text, Color color, Offset at) {
    final label = _label(text, color);
    label.paint(canvas, at);
    label.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.timesMs.length < 2 || curve.durationMs <= 0) {
      // Nothing recorded yet: an empty plot, waiting for the first samples.
      if (!compact) _paintEmpty(canvas, size);
      return;
    }
    final plot = plotRect(size, visible: visible, compact: compact);
    double x(int ms) => plot.left + plot.width * ms / curve.durationMs;
    final liquidTop = _top(true);
    final weightTop = _top(false);
    double y(CurveSeries series, double value) =>
        plot.bottom -
        plot.height *
            (value / (_isLiquid(series) ? liquidTop : weightTop)).clamp(
              0.0,
              1.0,
            );

    // Interpolate the actual painted segment, including axis clipping and
    // display downsampling. Readouts keep their original recorded values.
    Offset pointOnLine(CurveSeries series, int ms) {
      final times = display.timesMs;
      final values = display.values(series);
      final nearest = display.indexAt(ms);
      Offset point(int i) => Offset(x(times[i]), y(series, values[i]));
      if (ms <= times.first) return point(0);
      if (ms >= times.last) return point(times.length - 1);
      if (times[nearest] == ms) return point(nearest);
      final left = times[nearest] < ms ? nearest : nearest - 1;
      final right = left + 1;
      final fraction = (ms - times[left]) / (times[right] - times[left]);
      return Offset.lerp(point(left), point(right), fraction)!;
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final faint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    if (!compact) _paintAxes(canvas, plot, x, liquidTop, weightTop, faint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);

    if (targetWeightGrams case final target?
        when target > 0 && visible.contains(CurveSeries.weight)) {
      final dy = y(CurveSeries.weight, target);
      final paint = Paint()
        ..color = colors[CurveSeries.weight]!.withValues(alpha: 0.55)
        ..strokeWidth = 1.5;
      for (var dx = plot.left; dx < plot.right; dx += 10) {
        canvas.drawLine(
          Offset(dx, dy),
          Offset(math.min(dx + 6, plot.right), dy),
          paint,
        );
      }
      final label = _label(
        '${tickFormat.format(target)} g',
        colors[CurveSeries.weight]!,
      );
      label.paint(
        canvas,
        Offset(plot.left + 4, math.max(plot.top, dy - label.height - 3)),
      );
      label.dispose();
    }
    if (!compact && visible.contains(CurveSeries.weight)) {
      paintWeightTargets(
        canvas,
        plot,
        weightTargets,
        (grams) => y(CurveSeries.weight, grams),
        labelStyle,
        colors[CurveSeries.weight]!,
        targetAccent,
        background,
        drawLabels: false,
      );
    }
    for (final series in CurveSeries.values) {
      if (!visible.contains(series)) continue;
      final values = display.values(series);
      final path = Path()
        ..moveTo(x(display.timesMs.first), y(series, values.first));
      for (var i = 1; i < values.length; i++) {
        path.lineTo(x(display.timesMs[i]), y(series, values[i]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[series]!
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.5 : 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    if (!compact &&
        visible.contains(CurveSeries.pressure) &&
        recorded.pressure.isNotEmpty) {
      final peak = recorded.maxOf(CurveSeries.pressure);
      final index = recorded.pressure.indexOf(peak);
      final point = pointOnLine(CurveSeries.pressure, recorded.timesMs[index]);
      final color = colors[CurveSeries.pressure]!;
      canvas.drawCircle(point, 3.5, Paint()..color = color);
      final label = _label('${tickFormat.format(peak)} bar', color);
      label.paint(
        canvas,
        Offset(
          (point.dx + 7).clamp(
            plot.left,
            math.max(plot.left, plot.right - label.width),
          ),
          (point.dy - label.height - 4).clamp(
            plot.top + 2,
            plot.bottom - label.height,
          ),
        ),
      );
      label.dispose();
    }

    if (cursorMs case final ms?) {
      final cx = x(ms.clamp(0, curve.durationMs));
      canvas.drawLine(
        Offset(cx, plot.top),
        Offset(cx, plot.bottom),
        Paint()
          ..color = labelStyle.color!
          ..strokeWidth = 1.2,
      );
      for (final series in CurveSeries.values) {
        if (!visible.contains(series)) continue;
        canvas.drawCircle(
          pointOnLine(series, ms),
          4,
          Paint()..color = colors[series]!,
        );
      }
    }
    if (!compact && visible.contains(CurveSeries.weight)) {
      paintWeightTargets(
        canvas,
        plot,
        weightTargets,
        (grams) => y(CurveSeries.weight, grams),
        labelStyle,
        colors[CurveSeries.weight]!,
        targetAccent,
        background,
        drawLines: false,
      );
    }
  }

  /// The baseline, a few faint gridlines and the units of the axes in use.
  void _paintEmpty(Canvas canvas, Size size) {
    final plot = plotRect(size, visible: visible, compact: false);
    final faint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var line = 1; line <= 4; line++) {
      final dy = plot.bottom - plot.height * line / 4;
      canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), faint);
    }
    canvas.drawLine(
      plot.bottomLeft,
      plot.bottomRight,
      Paint()
        ..color = gridColor
        ..strokeWidth = 1,
    );
    if (visible.any(_isLiquid)) {
      _paintLabel(
        canvas,
        flowUnit,
        labelStyle.color!,
        Offset(plot.left - 28, 0),
      );
    }
    if (visible.contains(CurveSeries.weight)) {
      _paintLabel(
        canvas,
        'g',
        colors[CurveSeries.weight]!,
        Offset(plot.right + 5, 0),
      );
      paintWeightTargets(
        canvas,
        plot,
        weightTargets,
        (grams) =>
            plot.bottom - plot.height * (grams / _top(false)).clamp(0.0, 1.0),
        labelStyle,
        colors[CurveSeries.weight]!,
        targetAccent,
        background,
      );
    }
  }

  /// Gridlines, tick labels and units: bar · ml/s on the left, grams on the
  /// right in the weight's colour, seconds along the bottom.
  void _paintAxes(
    Canvas canvas,
    Rect plot,
    double Function(int ms) x,
    double liquidTop,
    double weightTop,
    Paint faint,
  ) {
    final neutral = labelStyle.color!;
    final weightColor = colors[CurveSeries.weight]!;
    final liquid = visible.any(_isLiquid);
    final weight = visible.contains(CurveSeries.weight);
    double level(double value, double top) =>
        plot.bottom - plot.height * value / top;

    if (liquid) {
      for (final tick in axisTicks(liquidTop)) {
        final dy = level(tick, liquidTop);
        canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), faint);
        final label = _label(tickFormat.format(tick), neutral);
        label.paint(
          canvas,
          Offset(plot.left - 5 - label.width, dy - label.height / 2),
        );
        label.dispose();
      }
      final unit = [
        if (visible.contains(CurveSeries.pressure)) 'bar',
        if (visible.contains(CurveSeries.flow)) flowUnit,
      ].join(', ');
      _paintLabel(canvas, unit, neutral, Offset(plot.left - 28, 0));
    }
    if (weight) {
      for (final tick in axisTicks(weightTop)) {
        final dy = level(tick, weightTop);
        if (!liquid) {
          canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), faint);
        }
        _paintLabel(
          canvas,
          tickFormat.format(tick),
          weightColor,
          Offset(plot.right + 5, dy - 7),
        );
      }
      final unit = _label('g', weightColor);
      unit.paint(canvas, Offset(plot.right + 5, 0));
      unit.dispose();
    }

    final seconds = curve.durationMs / 1000;
    for (final tick in axisTicks(seconds)) {
      if (tick > seconds) break;
      final ms = (tick * 1000).round();
      canvas.drawLine(
        Offset(x(ms), plot.top),
        Offset(x(ms), plot.bottom),
        faint,
      );
      final label = _label(formatDuration(ms ~/ 1000), neutral);
      final dx = (x(ms) - label.width / 2).clamp(
        plot.left - label.width / 2,
        plot.right - label.width,
      );
      label.paint(canvas, Offset(dx, plot.bottom + 4));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.targetWeightGrams != targetWeightGrams ||
      !listEquals(old._targetValues, _targetValues) ||
      old.targetAccent != targetAccent ||
      old.background != background ||
      old.curve != curve ||
      old.recorded != recorded ||
      old.display != display ||
      !mapEquals(old.peaks, peaks) ||
      !mapEquals(old.colors, colors) ||
      old.labelStyle != labelStyle ||
      old.tickFormat.locale != tickFormat.locale ||
      old.compact != compact ||
      old.flowUnit != flowUnit ||
      old.cursorMs != cursorMs ||
      old.gridColor != gridColor ||
      !setEquals(old.visible, visible);
}
