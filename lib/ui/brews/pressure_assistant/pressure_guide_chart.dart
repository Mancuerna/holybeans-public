import 'package:flutter/material.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';

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
  Widget build(BuildContext context) => ShotGuideChart(
    reference: [
      for (var i = 0; i < guide.timesMs.length; i++)
        (
          elapsedMs: guide.timesMs[i],
          value: guide.bars[i],
          breakBefore: i == 0,
        ),
    ],
    target: guide.targetAt(elapsedMs),
    unit: 'bar',
    minimumMaximum: 10,
    elapsedMs: elapsedMs,
    actual: actual,
    trace: [
      for (final point in trace)
        (
          elapsedMs: point.elapsedMs,
          value: point.bar,
          breakBefore: point.breakBefore,
        ),
    ],
  );
}
