import 'package:flutter/material.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Compact measurements under the plot, grouped by quantity. Time statistics
/// refer to the output window even while the cursor shows one instant.
class ExtractionReadout extends StatelessWidget {
  const ExtractionReadout({
    super.key,
    required this.curve,
    required this.visible,
    required this.flowUnit,
    required this.cursorMs,
    required this.flowStats,
    this.peaks,
    this.showTotals = false,
    this.showFlowStatistics = true,
  });

  final ShotCurve curve;
  final Set<CurveSeries> visible;
  final String flowUnit;
  final int? cursorMs;
  final CurveFlowStats? flowStats;
  final Map<CurveSeries, double>? peaks;
  final bool showTotals;
  final bool showFlowStatistics;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.0', regionalLocale.toString());
    final index = curve.indexAt(cursorMs ?? curve.durationMs);
    double peakOf(CurveSeries series) =>
        peaks?[series] ??
        (series == CurveSeries.pressure
            ? curve.maxOf(series)
            : curve.peakOf(series));
    String value(CurveSeries series, String unit) {
      if (index < 0 || curve.values(series).isEmpty) return '—';
      // Without a cursor every series shows its peak: a filter brew's last
      // weight drops when the brewer is lifted off the scale.
      if (cursorMs == null) {
        final peak = peakOf(series);
        return s.curvePeak('${number.format(peak)} $unit');
      }
      // Numerical readouts always use recorded measurements.
      final values = curve.values(series);
      return '${number.format(values[index])} $unit';
    }

    String flow(double? f) =>
        f == null ? '—' : number.format(f.abs() < 0.05 ? 0 : f);
    final stats = flowStats;
    return Column(
      key: const ValueKey('curve-readout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cursorMs != null || showTotals)
          _Line(
            values: [
              (
                s.time,
                formatDuration((cursorMs ?? curve.durationMs) ~/ 1000),
                'curve-duration',
              ),
              if (visible.contains(CurveSeries.weight))
                (
                  s.curveWeight,
                  value(CurveSeries.weight, 'g'),
                  'curve-weight-value',
                ),
            ],
          ),
        if (visible.contains(CurveSeries.pressure)) ...[
          const SizedBox(height: 4),
          _Line(
            values: [
              (
                s.curvePressure,
                value(CurveSeries.pressure, 'bar'),
                'curve-pressure-value',
              ),
            ],
          ),
        ],
        if (visible.contains(CurveSeries.flow)) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: !showFlowStatistics
                ? s.curveFlow
                : stats == null
                ? s.curveFlowWindowMissing
                : s.curveFlowWindow(
                    number.format(stats.startMs / 1000),
                    number.format(stats.endMs / 1000),
                  ),
            child: _Line(
              heading: '${s.curveFlow} ($flowUnit)',
              dense: true,
              values: [
                (
                  cursorMs == null ? s.curveFlowMaximum : s.curveFlowCurrent,
                  flow(
                    cursorMs == null
                        ? (showFlowStatistics ? stats?.max : null) ??
                              peakOf(CurveSeries.flow)
                        : (index < 0 ? null : curve.flow[index]),
                  ),
                  'curve-flow-value',
                ),
                if (showFlowStatistics) ...[
                  (s.curveFlowMean, flow(stats?.mean), 'curve-flow-mean'),
                  (s.curveFlowMedian, flow(stats?.median), 'curve-flow-median'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.values, this.heading, this.dense = false});

  final String? heading;
  final bool dense;

  final List<(String, String, String)> values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: dense ? 6 : 10,
    runSpacing: 4,
    children: [
      if (heading != null)
        Text(heading!, style: Theme.of(context).textTheme.labelMedium),
      for (final (label, value, key) in values)
        Wrap(
          key: ValueKey(key),
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style:
                  (dense
                          ? Theme.of(context).textTheme.labelMedium
                          : Theme.of(context).textTheme.labelLarge)
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
            ),
            Text(
              value,
              style:
                  (dense
                          ? Theme.of(context).textTheme.labelMedium
                          : Theme.of(context).textTheme.labelLarge)
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ],
        ),
    ],
  );
}
