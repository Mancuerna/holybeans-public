import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_readouts.dart';
import 'package:holybeans/ui/brews/pressure_assistant/shot_guide_chart.dart';
import 'package:intl/intl.dart';

class ProfileGuidePage extends StatefulWidget {
  const ProfileGuidePage({
    super.key,
    required this.profile,
    required this.timer,
    this.scale,
    this.pressure,
  });
  final ExtractionProfile profile;
  final BrewTimer timer;
  final BrewScaleSession? scale;
  final BrewPressureSession? pressure;
  @override
  State<ProfileGuidePage> createState() => _ProfileGuidePageState();
}

class _ProfileGuidePageState extends State<ProfileGuidePage> {
  final tick = Stopwatch();
  final updates = ValueNotifier(0);
  Timer? refresh;
  Timer? stale;
  StreamSubscription<double>? subscription;
  double? pressure;
  int get elapsed =>
      widget.timer.elapsedSeconds * 1000 +
      tick.elapsedMilliseconds.clamp(0, 999);
  void changed() => updates.value++;
  void clockChanged() {
    tick
      ..reset()
      ..stop();
    if (widget.timer.running) tick.start();
    changed();
  }

  void connectionChanged() {
    if (!(widget.pressure?.sensor.connected ?? false)) pressure = null;
    changed();
  }

  @override
  void initState() {
    super.initState();
    widget.timer.addListener(clockChanged);
    widget.scale?.addListener(changed);
    widget.scale?.scale.addListener(changed);
    widget.pressure?.sensor.addListener(connectionChanged);
    subscription = widget.pressure?.sensor.readings.listen((bar) {
      stale?.cancel();
      pressure = bar.isFinite && bar >= 0 && bar <= 30 ? bar : null;
      changed();
      stale = Timer(PressureTrace.staleAfter, () {
        pressure = null;
        changed();
      });
    });
    clockChanged();
    refresh = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (widget.timer.running) changed();
    });
  }

  @override
  void dispose() {
    widget.timer.removeListener(clockChanged);
    widget.scale?.removeListener(changed);
    widget.scale?.scale.removeListener(changed);
    widget.pressure?.sensor.removeListener(connectionChanged);
    refresh?.cancel();
    stale?.cancel();
    unawaited(subscription?.cancel());
    updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final p = widget.profile;
    final n = NumberFormat('0.0', Localizations.localeOf(context).toString());
    String value(double? v) => v == null ? '—' : n.format(v);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.timer.stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(p.name)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: updates,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${n.format(elapsed / 1000)} s',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (p.flow.isNotEmpty)
                    Text(
                      '${value(widget.scale?.guideWeightGrams)} / ${value(p.predictedGrams ?? p.targetGrams)} g',
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: widget.timer.running || widget.timer.canStart
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
                        IconButton.outlined(
                          onPressed: widget.timer.reset,
                          tooltip: s.resetTimer,
                          icon: const Icon(Icons.restart_alt),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: updates,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExpansionTile(
                  title: Text(s.shotAssistant),
                  children: [Text(s.profileManual), Text(s.profileClock)],
                ),
                const SizedBox(height: 12),
                if (elapsed > p.durationMs) Text(s.pressureGuideComplete),
                for (final channel in [
                  p.primary,
                  p.primary == 'flow' ? 'pressure' : 'flow',
                ])
                  if ((channel == 'flow' ? p.flow : p.pressure).isNotEmpty) ...[
                    Text(
                      channel == 'flow' ? s.curveFlow : s.curvePressure,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (p.flow.isEmpty || p.pressure.isEmpty)
                      PressureReadouts(
                        target: value(
                          p.targetAt(
                            channel == 'flow' ? p.flow : p.pressure,
                            elapsed,
                          ),
                        ),
                        actual: value(
                          !widget.timer.running
                              ? null
                              : channel == 'flow'
                              ? widget.scale?.flowGramsPerSecond
                              : pressure,
                        ),
                        unit: channel == 'flow' ? 'g/s' : 'bar',
                        keyPrefix: 'profile-$channel',
                        actualLabel: channel == 'flow'
                            ? s.flowGuideActual
                            : null,
                      ),
                    if (p.flow.isNotEmpty && p.pressure.isNotEmpty)
                      Wrap(
                        spacing: 20,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${s.pressureGuideTarget}: ${value(p.targetAt(channel == 'flow' ? p.flow : p.pressure, elapsed))} ${channel == 'flow' ? 'g/s' : 'bar'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${channel == 'flow' ? s.flowGuideActual : s.pressureGuideActual}: ${value(!widget.timer.running
                                ? null
                                : channel == 'flow'
                                ? widget.scale?.flowGramsPerSecond
                                : pressure)} ${channel == 'flow' ? 'g/s' : 'bar'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    Text(
                      '${s.pressureGuideAhead}: ${value(p.targetAt(channel == 'flow' ? p.flow : p.pressure, elapsed + 2000))} ${channel == 'flow' ? 'g/s' : 'bar'}',
                    ),
                    ShotGuideChart(
                      height: p.flow.isNotEmpty && p.pressure.isNotEmpty
                          ? 145
                          : 250,
                      reference: channel == 'flow' ? p.flow : p.pressure,
                      target: p.targetAt(
                        channel == 'flow' ? p.flow : p.pressure,
                        elapsed,
                      ),
                      elapsedMs: elapsed,
                      actual: !widget.timer.running
                          ? null
                          : channel == 'flow'
                          ? widget.scale?.flowGramsPerSecond
                          : pressure,
                      trace: channel == 'flow'
                          ? widget.scale?.flowTrace.points ?? const []
                          : [
                              for (final point
                                  in widget.pressure?.trace.points ??
                                      <PressureTracePoint>[])
                                (
                                  elapsedMs: point.elapsedMs,
                                  value: point.bar,
                                  breakBefore: point.breakBefore,
                                ),
                            ],
                      unit: channel == 'flow' ? 'g/s' : 'bar',
                    ),
                    if (channel == 'flow' &&
                        widget.scale?.scale.connected != true)
                      Text(s.flowGuideConnect),
                    if (channel == 'flow' &&
                        widget.scale?.scale.connected == true &&
                        widget.timer.running &&
                        widget.scale?.flowGramsPerSecond == null)
                      Text(
                        widget.scale!.hasRecentFlowReading
                            ? s.flowGuideWaiting
                            : s.flowGuideStale,
                      ),
                    if (channel == 'pressure' && pressure == null)
                      Text(s.pressureGuideManual),
                    const SizedBox(height: 16),
                  ],
                if (p.weightAt(elapsed) case final weight?)
                  Text(s.flowGuideExpectedWeight(value(weight))),
                Text(s.pressureGuideExit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
