import 'package:flutter/material.dart';
import 'package:holybeans/domain/brew_comparison.dart';
import 'package:holybeans/domain/comparison_timeline.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/comparison_playback.dart';
import 'package:holybeans/ui/brews/comparison_plot.dart';
import 'package:holybeans/ui/brews/comparison_values_row.dart';
import 'package:holybeans/ui/brews/espresso_combined_plot.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/regional_numbers.dart';
import 'package:intl/intl.dart';

class EspressoComparisonCurves extends StatefulWidget {
  const EspressoComparisonCurves({
    super.key,
    required this.a,
    required this.b,
    this.firstDripA,
    this.firstDripB,
    this.durationA,
    this.durationB,
    this.beverageA,
    this.beverageB,
  });
  final ComparisonCurve? a;
  final ComparisonCurve? b;
  final int? firstDripA;
  final int? firstDripB;
  final double? durationA;
  final double? durationB;
  final double? beverageA;
  final double? beverageB;

  @override
  State<EspressoComparisonCurves> createState() =>
      _EspressoComparisonCurvesState();
}

class _EspressoComparisonCurvesState extends State<EspressoComparisonCurves>
    with SingleTickerProviderStateMixin, ComparisonPlayback {
  ComparisonAlignment alignment = ComparisonAlignment.start;
  final position = ValueNotifier(0.0);
  bool combined = true;

  late ComparisonTimeline timeline;

  @override
  void initState() {
    super.initState();
    _prepareTimeline();
  }

  @override
  void didUpdateWidget(EspressoComparisonCurves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.a != oldWidget.a ||
        widget.b != oldWidget.b ||
        widget.firstDripA != oldWidget.firstDripA ||
        widget.firstDripB != oldWidget.firstDripB) {
      _prepareTimeline();
    }
  }

  @override
  double get playbackPosition => position.value;

  @override
  void updatePlaybackPosition(double value) => position.value = value;

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  void _prepareTimeline() {
    pausePlayback();
    timeline = ComparisonTimeline(
      a: widget.a,
      b: widget.b,
      firstDripA: widget.firstDripA,
      firstDripB: widget.firstDripB,
      alignment: alignment,
    );
  }

  void _seek(double time) {
    pausePlayback();
    updatePlaybackPosition(time);
  }

  Widget _highlights(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.#', regionalLocale.toString())
      ..turnOffGrouping();
    final pressureA = timeline.peak(CurveSeries.pressure, second: false);
    final pressureB = timeline.peak(CurveSeries.pressure, second: true);
    final flowA = timeline.peak(CurveSeries.flow, second: false);
    final flowB = timeline.peak(CurveSeries.flow, second: true);
    Widget metric(
      String title,
      double? a,
      double? b,
      String unit, {
      String? secondUnit,
      bool comparable = true,
    }) {
      final scheme = Theme.of(context).colorScheme;
      String present(double? value, String suffix) => value == null
          ? s.comparisonMissing
          : '${number.format(value)} $suffix';
      final delta = comparable && a != null && b != null && a != 0
          ? (b - a) / a * 100
          : null;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 3),
              Text(
                'A  ${present(a, unit)}',
                style: AppTheme.figures(
                  Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'B  ${present(b, secondUnit ?? unit)}',
                style: AppTheme.figures(Theme.of(context).textTheme.bodyMedium),
              ),
              if (delta != null)
                Text(
                  'B − A  ${delta > 0 ? '+' : ''}${number.format(delta)} %',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 600
            ? (constraints.maxWidth - 24) / 4
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.durationA != null || widget.durationB != null)
              SizedBox(
                width: width,
                child: metric(
                  s.extractionDuration,
                  widget.durationA,
                  widget.durationB,
                  's',
                ),
              ),
            if (widget.beverageA != null || widget.beverageB != null)
              SizedBox(
                width: width,
                child: metric(
                  s.curveWeight,
                  widget.beverageA,
                  widget.beverageB,
                  'g',
                ),
              ),
            if (pressureA != null || pressureB != null)
              SizedBox(
                width: width,
                child: metric(
                  s.comparisonPeakPressure,
                  pressureA,
                  pressureB,
                  'bar',
                ),
              ),
            if (flowA != null || flowB != null)
              SizedBox(
                width: width,
                child: metric(
                  s.comparisonPeakFlow,
                  flowA,
                  flowB,
                  widget.a?.flowUnit ?? widget.b?.flowUnit ?? 'g/s',
                  secondUnit: widget.b?.flowUnit,
                  comparable:
                      widget.a == null ||
                      widget.b == null ||
                      widget.a!.flowUnit == widget.b!.flowUnit,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _combinedView(
    BuildContext context,
    double cursor,
    bool flowCompatible,
  ) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.#', regionalLocale.toString())
      ..turnOffGrouping();
    String value(CurveSeries series, bool second) {
      final point = timeline.at(series, cursor, second: second);
      final curve = second ? widget.b : widget.a;
      return point == null
          ? s.comparisonMissing
          : '${number.format(point)} ${curve!.unit(series)}';
    }

    Widget legend(Color color, String title) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(title)),
      ],
    );
    Widget readout(String letter, bool second) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$letter  ${s.curvePressure}: ${value(CurveSeries.pressure, second)}   '
        '${s.curveFlow}: ${value(CurveSeries.flow, second)}   '
        '${s.curveWeight}: ${value(CurveSeries.weight, second)}',
        key: ValueKey('espresso-combined-value-${letter.toLowerCase()}'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EspressoCombinedPlot(
          key: const ValueKey('espresso-combined-plot'),
          timeline: timeline,
          cursorMs: cursor,
          locale: s.localeName,
          flowCompatible: flowCompatible,
          onChanged: _seek,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            legend(
              curveSeriesColor(context, CurveSeries.pressure),
              '${s.curvePressure} (bar)',
            ),
            if (flowCompatible)
              legend(
                curveSeriesColor(context, CurveSeries.flow),
                '${s.curveFlow} (${widget.a?.flowUnit ?? widget.b?.flowUnit ?? 'g/s'})',
              ),
            legend(
              curveSeriesColor(context, CurveSeries.weight),
              '${s.curveWeight} (g)',
            ),
          ],
        ),
        if (!flowCompatible)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.comparisonFlowUnits,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        Text(
          '${number.format(cursor / 1000)} s    A ━    B ┄',
          key: const ValueKey('espresso-cursor-time'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        readout('A', false),
        readout('B', true),
      ],
    );
  }

  Widget _panel(BuildContext context, CurveSeries series, double cursor) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final number = NumberFormat('0.##', regionalLocale.toString())
      ..turnOffGrouping();
    String label(CurveSeries series) => switch (series) {
      CurveSeries.pressure => s.curvePressure,
      CurveSeries.flow => s.curveFlow,
      CurveSeries.weight => s.curveWeight,
    };
    String value(CurveSeries series, bool second) {
      final v = timeline.at(series, cursor, second: second);
      final curve = second ? widget.b : widget.a;
      return v == null
          ? s.comparisonMissing
          : '${number.format(v)} ${curve!.unit(series)}';
    }

    final first = timeline.samples(series, second: false);
    final second = timeline.samples(series, second: true);
    final split =
        first.isNotEmpty &&
        second.isNotEmpty &&
        !canOverlayCurves(widget.a!, widget.b!, series);
    final delta = timeline.difference(series, cursor);
    Widget plot(bool a, bool b) => ComparisonPlot(
      color: curveSeriesColor(context, series),
      key: ValueKey(
        'espresso-plot-${a && b
            ? 'both'
            : a
            ? 'a'
            : 'b'}-${series.name}',
      ),
      first: a ? first : [],
      second: b ? second : [],
      minMs: timeline.minMs.toDouble(),
      maxMs: timeline.maxMs.toDouble(),
      cursorMs: cursor,
      locale: s.localeName,
      onChanged: _seek,
      label: '${label(series)}, ${number.format(cursor / 1000)} s',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label(series), style: theme.textTheme.titleSmall),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'A ━ ${value(series, false)}',
                key: ValueKey('espresso-value-a-${series.name}'),
              ),
              Text(
                'B ┄ ${value(series, true)}',
                key: ValueKey('espresso-value-b-${series.name}'),
              ),
              if (delta != null)
                Text(
                  'Δ B − A: ${delta > 0 ? '+' : ''}${number.format(delta.abs() < .000001 ? 0 : delta)} ${widget.a!.unit(series)}',
                  key: ValueKey('espresso-delta-${series.name}'),
                ),
            ],
          ),
          if (first.isEmpty && second.isEmpty)
            Text(s.comparisonMissing)
          else if (split) ...[
            Text(s.comparisonFlowUnits, style: theme.textTheme.bodySmall),
            Text('A (${widget.a!.unit(series)})'),
            plot(true, false),
            Text('B (${widget.b!.unit(series)})'),
            plot(false, true),
          ] else ...[
            Text(
              (first.isNotEmpty ? widget.a : widget.b)!.unit(series),
              style: theme.textTheme.bodySmall,
            ),
            plot(first.isNotEmpty, second.isNotEmpty),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget atCursor(Widget Function(double) builder) => ValueListenableBuilder(
      valueListenable: position,
      builder: (_, value, _) => builder(
        value.clamp(timeline.minMs.toDouble(), timeline.maxMs.toDouble()),
      ),
    );
    final number = RegionalNumberFormat('0.##');
    final hasCurve = CurveSeries.values.any(
      (series) =>
          timeline.samples(series, second: false).isNotEmpty ||
          timeline.samples(series, second: true).isNotEmpty,
    );
    final flowCompatible =
        widget.a == null ||
        widget.b == null ||
        widget.a!.flowUnit == widget.b!.flowUnit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.a == null) Text('A: ${s.comparisonCurvesMissing}'),
        if (widget.b == null) Text('B: ${s.comparisonCurvesMissing}'),
        if (hasCurve) ...[
          Text(s.extractionCurve, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          // Two choices of the same kind, drawn the same way: how the
          // curves are laid out, then where they start.
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(
                  s.comparisonCombined,
                  key: const ValueKey('espresso-combined-mode'),
                ),
              ),
              ButtonSegment(
                value: false,
                label: Text(
                  s.comparisonSeparated,
                  key: const ValueKey('espresso-separated-mode'),
                ),
              ),
            ],
            selected: {combined},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => combined = value.single),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ComparisonAlignment>(
            segments: [
              ButtonSegment(
                value: ComparisonAlignment.start,
                label: Text(s.comparisonAlignStart),
              ),
              ButtonSegment(
                value: ComparisonAlignment.firstDrip,
                label: Text(s.firstDrip),
                enabled: timeline.canAlignDrip,
              ),
            ],
            selected: {timeline.alignment},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() {
              alignment = value.single;
              _prepareTimeline();
              position.value = 0;
            }),
          ),
          if (!timeline.canAlignDrip)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.comparisonAlignmentUnavailable,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (combined)
            atCursor((cursor) => _combinedView(context, cursor, flowCompatible))
          else ...[
            atCursor((cursor) => _panel(context, CurveSeries.pressure, cursor)),
            atCursor((cursor) => _panel(context, CurveSeries.flow, cursor)),
            ExpansionTile(
              key: const ValueKey('espresso-weight-toggle'),
              tilePadding: EdgeInsets.zero,
              title: Text(s.curveWeight),
              children: [
                atCursor(
                  (cursor) => _panel(context, CurveSeries.weight, cursor),
                ),
              ],
            ),
          ],
          Text(
            timeline.alignment == ComparisonAlignment.start
                ? s.comparisonTimeFromStart
                : s.comparisonTimeFromDrip,
            style: theme.textTheme.labelLarge,
          ),
          Row(
            children: [
              playbackButton(
                min: timeline.minMs.toDouble(),
                max: timeline.maxMs.toDouble(),
              ),
              Expanded(
                child: atCursor(
                  (cursor) => Slider(
                    key: const ValueKey('espresso-comparison-time'),
                    value: cursor,
                    min: timeline.minMs.toDouble(),
                    max: timeline.maxMs.toDouble(),
                    label: '${number.format(cursor / 1000)} s',
                    semanticFormatterCallback: (v) =>
                        '${number.format(v / 1000)} s',
                    onChangeStart: (_) => pausePlayback(),
                    onChanged: _seek,
                  ),
                ),
              ),
            ],
          ),
          if (!combined)
            atCursor(
              (cursor) => Text(
                '${number.format(cursor / 1000)} s',
                key: const ValueKey('espresso-cursor-time'),
              ),
            ),
          Text(s.comparisonCursorHint, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        _highlights(context),
      ],
    );
  }
}

class EspressoCurveSummary extends StatelessWidget {
  const EspressoCurveSummary({
    super.key,
    required this.a,
    required this.b,
    this.firstDripA,
    this.firstDripB,
  });
  final ComparisonCurve? a;
  final ComparisonCurve? b;
  final int? firstDripA;
  final int? firstDripB;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final timeline = ComparisonTimeline(a: a, b: b);
    final first = a == null
        ? null
        : CurveFlowStats.fromCurve(a!.curve, firstDripMs: firstDripA);
    final second = b == null
        ? null
        : CurveFlowStats.fromCurve(b!.curve, firstDripMs: firstDripB);
    final number = NumberFormat('0.##', regionalLocale.toString())
      ..turnOffGrouping();
    String? value(double? n, String? unit) =>
        n == null ? null : '${number.format(n)} $unit';
    Widget row(
      String label,
      double? x,
      double? y,
      String? unitA,
      String? unitB,
    ) {
      final delta = x == null || y == null || unitA != unitB ? null : y - x;
      return ComparisonValuesRow(
        label: label,
        a: value(x, unitA),
        b: value(y, unitB),
        difference: delta == null
            ? null
            : '${s.comparisonDifference}: ${delta > 0 ? '+' : ''}${value(delta.abs() < .000001 ? 0 : delta, unitA)}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          s.comparisonRecordedPeak,
          timeline.peak(CurveSeries.pressure, second: false),
          timeline.peak(CurveSeries.pressure, second: true),
          'bar',
          'bar',
        ),
        row(
          s.comparisonFlowMean,
          first?.mean,
          second?.mean,
          a?.flowUnit,
          b?.flowUnit,
        ),
        row(
          s.comparisonFlowMedian,
          first?.median,
          second?.median,
          a?.flowUnit,
          b?.flowUnit,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            s.comparisonFlowStatsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
