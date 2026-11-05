import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_readouts.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';
import 'package:intl/intl.dart';

class FlowGuidePage extends StatefulWidget {
  const FlowGuidePage({
    super.key,
    required this.guide,
    required this.title,
    required this.timer,
    this.session,
    this.targetWeightGrams,
  });

  final FlowGuide guide;
  final String title;
  final BrewTimer timer;
  final BrewScaleSession? session;
  final double? targetWeightGrams;

  @override
  State<FlowGuidePage> createState() => _FlowGuidePageState();
}

class _FlowGuidePageState extends State<FlowGuidePage> {
  final _sinceTick = Stopwatch();
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    widget.timer.addListener(_clockChanged);
    widget.session?.addListener(_changed);
    widget.session?.scale.addListener(_changed);
    _clockChanged();
    _refresh = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (widget.timer.running) _changed();
    });
  }

  void _changed() => setState(() {});

  void _clockChanged() {
    _sinceTick
      ..reset()
      ..stop();
    if (widget.timer.running) _sinceTick.start();
    _changed();
  }

  @override
  void dispose() {
    widget.timer.removeListener(_clockChanged);
    widget.session?.removeListener(_changed);
    widget.session?.scale.removeListener(_changed);
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final elapsed =
        widget.timer.elapsedSeconds * 1000 +
        _sinceTick.elapsedMilliseconds.clamp(0, 999);
    final target = widget.guide.targetAt(elapsed);
    final next = widget.guide.targetAt(elapsed + 2000);
    final connected = widget.session?.scale.connected ?? false;
    final actual = widget.timer.running
        ? widget.session?.flowGramsPerSecond
        : null;
    final number = NumberFormat(
      '0.0',
      Localizations.localeOf(context).toString(),
    );
    String value(double? flow) => flow == null ? '—' : number.format(flow);
    final weight = widget.session?.guideWeightGrams;
    final savedTarget = widget.targetWeightGrams;
    final finalWeight =
        savedTarget != null && savedTarget.isFinite && savedTarget > 0
        ? savedTarget
        : widget.guide.finalWeightGrams;
    final referenceWeight = widget.guide.weightAt(elapsed);
    final weightDifference = weight == null || referenceWeight == null
        ? null
        : weight - referenceWeight;
    final difference = target == null || actual == null
        ? null
        : actual - target;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.timer.stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.flowAssistant)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.flowGuideWeightLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${value(weight)} / ${value(finalWeight)} g',
                  key: const ValueKey('flow-guide-weight'),
                  semanticsLabel: s.flowGuideWeightProgress(
                    value(weight),
                    value(finalWeight),
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(elapsed / 1000).toStringAsFixed(1)} s',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('flow-guide-toggle'),
                      onPressed:
                          widget.timer.running ||
                              (connected && widget.timer.canStart)
                          ? widget.timer.toggle
                          : null,
                      icon: Icon(
                        widget.timer.running ? Icons.stop : Icons.play_arrow,
                      ),
                      label: Text(
                        widget.timer.running ? s.stopTimer : s.startTimer,
                      ),
                    ),
                    if (!widget.timer.running)
                      OutlinedButton.icon(
                        key: const ValueKey('flow-guide-reset'),
                        onPressed: widget.timer.reset,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(s.resetTimer),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (!widget.timer.running) Text(s.flowGuideInstructions),
                if (!connected) Text(s.flowGuideConnect),
                const SizedBox(height: 20),
                if (elapsed > widget.guide.endMs) Text(s.pressureGuideComplete),
                PressureReadouts(
                  target: value(target),
                  actual: value(actual),
                  unit: 'g/s',
                  actualLabel: s.flowGuideActual,
                  keyPrefix: 'flow',
                ),
                const SizedBox(height: 12),
                Text('${s.pressureGuideAhead}: ${value(next)} g/s'),
                if (difference != null)
                  Text(
                    difference.abs() < 0.1
                        ? s.flowGuideOnTarget
                        : difference > 0
                        ? s.flowGuideAbove(number.format(difference))
                        : s.flowGuideBelow(number.format(-difference)),
                    key: const ValueKey('flow-guide-difference'),
                  ),
                const SizedBox(height: 8),
                Text(
                  s.flowGuideExpectedWeight(value(referenceWeight)),
                  key: const ValueKey('flow-guide-expected-weight'),
                ),
                if (weightDifference != null)
                  Text(
                    s.flowGuideWeightDifference(
                      '${weightDifference.abs() < 0.05
                          ? ''
                          : weightDifference > 0
                          ? '+'
                          : '−'}${number.format(weightDifference.abs())}',
                    ),
                    key: const ValueKey('flow-guide-weight-difference'),
                  ),
                ShotGuideChart(
                  reference: widget.guide.points,
                  target: target,
                  elapsedMs: elapsed,
                  actual: actual,
                  trace: widget.session?.flowTrace.points ?? const [],
                  unit: 'g/s',
                ),
                Text(s.flowGuideMarkers),
                const SizedBox(height: 8),
                Text(s.flowGuideSmoothing),
                if (connected && widget.timer.running && actual == null)
                  Text(
                    widget.session!.hasRecentFlowReading
                        ? s.flowGuideWaiting
                        : s.flowGuideStale,
                  ),
                const SizedBox(height: 20),
                Text(s.pressureGuideExit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
