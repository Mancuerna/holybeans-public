import 'package:flutter/material.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';

class PressureGuideChart extends StatefulWidget {
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
  State<PressureGuideChart> createState() => _PressureGuideChartState();
}

class _PressureGuideChartState extends State<PressureGuideChart> {
  late List<GuidePoint> _reference = _referencePoints();
  late List<GuidePoint> _trace = _tracePoints();

  List<GuidePoint> _referencePoints() => [
    for (var i = 0; i < widget.guide.timesMs.length; i++)
      (
        elapsedMs: widget.guide.timesMs[i],
        value: widget.guide.bars[i],
        breakBefore: i == 0,
      ),
  ];

  List<GuidePoint> _tracePoints() => [
    for (final point in widget.trace)
      (
        elapsedMs: point.elapsedMs,
        value: point.bar,
        breakBefore: point.breakBefore,
      ),
  ];

  @override
  void didUpdateWidget(PressureGuideChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.guide != oldWidget.guide) _reference = _referencePoints();
    if (widget.trace != oldWidget.trace) _trace = _tracePoints();
  }

  @override
  Widget build(BuildContext context) => ShotGuideChart(
    reference: _reference,
    target: widget.guide.targetAt(widget.elapsedMs),
    unit: 'bar',
    minimumMaximum: 10,
    elapsedMs: widget.elapsedMs,
    actual: widget.actual,
    trace: _trace,
  );
}
