import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/services/brew_live_notice.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/manual_pour_run.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_bars.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_chart.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_step_card.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// What a finished run hands back: the brew time in seconds and, with a
/// scale, the weight curve and the water poured (its peak).
typedef PourFinish = void Function(
  int seconds, {
  ShotCurve? curve,
  double? pouredGrams,
});

/// Follows a pour plan: the clock, the step to pour now and the next one,
/// with three short beeps before each step and a long one when it starts.
/// With a connected [scale], it tares it and starts its timer, shows how
/// much is left for the step and draws the real weight over the plan.
class PourRunView extends StatefulWidget {
  const PourRunView({
    super.key,
    required this.plan,
    required this.feedback,
    required this.onFinish,
    this.stopwatch = Stopwatch.new,
    this.scale,
    this.atYourPace = false,
  });

  final PourPlan plan;
  final DeviceFeedback feedback;
  final PourFinish onFinish;
  final Scale? scale;
  final bool atYourPace;

  /// Measures the brew; tests pass one they can move by hand.
  final Stopwatch Function() stopwatch;

  @override
  State<PourRunView> createState() => _PourRunViewState();
}

class _PourRunViewState extends State<PourRunView> {
  late final watch = widget.stopwatch();
  final recording = WeightRecording();
  late final manual = ManualPourRun(widget.plan);
  bool announcedDrain = false;
  StreamSubscription<ScaleReading>? readings;
  Timer? ticker;
  int lastCueSecond = -1;

  /// The step the ongoing notification shows, so it changes once a step.
  PourStep? announced;
  final startedAt = DateTime.now();

  int get second => watch.elapsed.inSeconds;

  /// The scale, while it is connected.
  Scale? get scale => switch (widget.scale) {
    final scale? when scale.connected => scale,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    widget.feedback.keepScreenOn(true);
    if (scale case final scale?) {
      recording.restartAfterTare();
      scale.send(ScaleCommand.tareAndStartTimer);
    }
    readings = widget.scale?.readings.listen((reading) {
      if (watch.isRunning) recording.add(watch.elapsedMilliseconds, reading);
    });
    watch.start();
    if (widget.atYourPace) {
      widget.feedback.beep(long: true);
    } else {
      _cue(0);
    }
    lastCueSecond = 0;
    ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    watch.stop();
    ticker?.cancel();
    readings?.cancel();
    unawaited(const BrewLiveNotice().clear());
    widget.feedback.keepScreenOn(false);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    _announce();
    if (widget.atYourPace) {
      if (watch.isRunning) {
        final cue = manual.cueAt(watch.elapsedMilliseconds);
        if (cue != null) widget.feedback.beep(long: cue == PourCue.long);
      }
      return;
    }
    if (watch.isRunning && second != lastCueSecond) {
      lastCueSecond = second;
      _cue(second);
    }
  }

  /// Beeps for a countdown to the next step, its start, or the end of the
  /// pouring.
  void _cue(int now) {
    for (final step in widget.plan.steps) {
      final left = step.startSecond - now;
      if (left == 0) {
        widget.feedback.beep(long: true);
        return;
      }
      if (left > 0 && left <= 3) {
        widget.feedback.beep();
        return;
      }
    }
    if (now == widget.plan.pouringEndSecond) widget.feedback.beep(long: true);
  }

  /// The current step on the lock screen: which pour, to what weight, and
  /// the steps as segments filled up to what is poured.
  void _announce() {
    if (widget.atYourPace && !watch.isRunning) return;
    if (widget.atYourPace && manual.draining) {
      if (!announcedDrain) {
        announcedDrain = true;
        final s = AppLocalizations.of(context);
        unawaited(
          const BrewLiveNotice().showPours(
            title: s.drawdown,
            text: s.totalWater(
              formatDecimal(
                widget.plan.totalWaterGrams,
                pattern: '0',
                locale: regionalLocale.toString(),
              ),
            ),
            startedAt: widget.atYourPace
                ? DateTime.now().subtract(watch.elapsed)
                : startedAt,
            segments: [
              for (final each in widget.plan.steps) each.addGrams.round(),
            ],
            poured: (recording.peakGrams ?? widget.plan.totalWaterGrams)
                .round(),
          ),
        );
      }
      return;
    }
    final step = widget.atYourPace
        ? manual.current
        : widget.plan.stepAt(second);
    // Steps are built anew on every call: the same step has the same kind
    // and number.
    if (step == null ||
        (step.kind == announced?.kind && step.number == announced?.number)) {
      return;
    }
    announced = step;
    final s = AppLocalizations.of(context);
    final grams = NumberFormat('0', regionalLocale.toString());
    final steps = widget.plan.steps;
    unawaited(
      const BrewLiveNotice().showPours(
        title: step.kind == PourStepKind.bloom
            ? s.bloomNumber(step.number)
            : s.pourStepPour(step.number, widget.plan.pours),
        text: s.pourTo(grams.format(step.targetGrams)),
        startedAt: widget.atYourPace
            ? DateTime.now().subtract(watch.elapsed)
            : startedAt,
        segments: [for (final each in steps) each.addGrams.round()],
        poured: (recording.peakGrams ?? step.targetGrams - step.addGrams)
            .round(),
      ),
    );
  }

  void _advance() {
    if (!watch.isRunning || manual.draining) return;
    setState(() => manual.advance(watch.elapsedMilliseconds));
    widget.feedback.beep(long: true);
    _announce();
  }

  void _togglePause() {
    final running = watch.isRunning;
    setState(running ? watch.stop : watch.start);
    scale?.send(running ? ScaleCommand.stopTimer : ScaleCommand.startTimer);
    if (widget.atYourPace) {
      if (running) {
        unawaited(const BrewLiveNotice().clear());
      } else {
        announced = null;
        announcedDrain = false;
        _announce();
      }
    }
  }

  void _finish(int seconds) {
    watch.stop();
    unawaited(const BrewLiveNotice().clear());
    scale?.send(ScaleCommand.stopTimer);
    widget.onFinish(
      seconds,
      curve: recording.curve,
      pouredGrams: recording.peakGrams,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grams = NumberFormat('0', regionalLocale.toString());
    final plan = widget.plan;
    final now = second;
    final current = widget.atYourPace ? manual.current : plan.stepAt(now);
    final next = widget.atYourPace ? manual.next : plan.nextAfter(now);
    final remaining = widget.atYourPace
        ? manual.remainingSeconds(watch.elapsedMilliseconds)
        : next == null
        ? null
        : next.startSecond - now;
    final pouringDone = widget.atYourPace
        ? manual.draining
        : next == null && now >= plan.pouringEndSecond;
    final onScale = scale == null ? null : recording.lastGrams;
    String clock(int seconds) => formatDuration(seconds);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Center(
                child: Text(
                  clock(now),
                  key: const ValueKey('pour-clock'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PourStepCard(
                plan: plan,
                current: current,
                pouringDone: pouringDone,
                onScale: onScale,
                atYourPace: widget.atYourPace,
              ),
              if (next != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    widget.atYourPace && remaining == 0
                        ? s.pourWhenReady
                        : s.nextPour(
                            remaining!,
                            grams.format(next.targetGrams),
                          ),
                    key: const ValueKey('pour-next-step'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              const SizedBox(height: 8),
              PourBars(
                plan: plan,
                showSchedule: !widget.atYourPace,
                second: widget.atYourPace ? manual.barSecond : now,
                grams: onScale,
              ),
              ExpansionTile(
                title: Text(s.pourRecordedCurve),
                children: [
                  if (widget.atYourPace)
                    if (recording.curve case final curve?)
                      ExtractionChart(
                        curve: curve,
                        live: true,
                        interactive: false,
                        replayable: false,
                        showReadout: false,
                        flowUnit: 'g/s',
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(s.pourManualCurveHint),
                      )
                  else
                    PourChart(
                      plan: plan,
                      elapsedSeconds: watch.elapsedMilliseconds / 1000,
                      actual: recording.curve,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (widget.atYourPace && !manual.draining)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('pour-advance'),
                onPressed: watch.isRunning ? _advance : null,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(
                  next == null
                      ? s.pourStartDrawdown
                      : next.kind == PourStepKind.bloom
                      ? s.pourStartNextBloom
                      : s.pourStartNext,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('pour-pause'),
                  onPressed: _togglePause,
                  icon: Icon(
                    watch.isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    watch.isRunning ? s.pausePouring : s.resumePouring,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('pour-finish'),
                  onPressed: () => _finish(now),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(s.finishPouring),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
