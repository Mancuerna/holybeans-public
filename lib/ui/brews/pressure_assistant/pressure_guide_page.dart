import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/pressure_trace.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pressure_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_chart.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_readouts.dart';
import 'package:intl/intl.dart';

class PressureGuidePage extends StatefulWidget {
  const PressureGuidePage({
    super.key,
    required this.guide,
    required this.title,
    required this.timer,
    this.session,
  });
  final PressureGuide guide;
  final String title;
  final BrewTimer timer;
  final BrewPressureSession? session;

  @override
  State<PressureGuidePage> createState() => _PressureGuidePageState();
}

class _PressureGuidePageState extends State<PressureGuidePage> {
  final _sinceTick = Stopwatch();
  final _updates = ValueNotifier(0);
  final _controls = ValueNotifier((running: false, canStart: true));
  int get _elapsed =>
      widget.timer.elapsedSeconds * 1000 +
      _sinceTick.elapsedMilliseconds.clamp(0, 999);
  Timer? _refresh;
  Timer? _stale;
  StreamSubscription<double>? _readings;
  double? _actual;

  @override
  void initState() {
    super.initState();
    widget.timer.addListener(_clockChanged);
    widget.session?.sensor.addListener(_connectionChanged);
    _readings = widget.session?.sensor.readings.listen((bar) {
      _stale?.cancel();
      _actual = bar.isFinite && bar >= 0 && bar <= 30 ? bar : null;
      _changed();
      _stale = Timer(PressureTrace.staleAfter, () {
        if (mounted) {
          _actual = null;
          _changed();
        }
      });
    });
    _clockChanged();
    _refresh = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (widget.timer.running) _changed();
    });
  }

  void _changed() {
    _controls.value = (
      running: widget.timer.running,
      canStart: widget.timer.canStart,
    );
    _updates.value++;
  }

  void _clockChanged() {
    _sinceTick
      ..reset()
      ..stop();
    if (widget.timer.running) _sinceTick.start();
    _changed();
  }

  void _connectionChanged() {
    if (!(widget.session?.sensor.connected ?? false)) {
      _actual = null;
      _changed();
    }
  }

  @override
  void dispose() {
    widget.timer.removeListener(_clockChanged);
    widget.session?.sensor.removeListener(_connectionChanged);
    _refresh?.cancel();
    _stale?.cancel();
    unawaited(_readings?.cancel());
    _updates.dispose();
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.timer.stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.pressureAssistant)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListenableBuilder(
                  listenable: _updates,
                  builder: (context, _) => Text(
                    '${(_elapsed / 1000).toStringAsFixed(1)} s',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder(
                  valueListenable: _controls,
                  builder: (context, controls, _) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('pressure-guide-toggle'),
                        onPressed: controls.running || controls.canStart
                            ? widget.timer.toggle
                            : null,
                        icon: Icon(
                          controls.running ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          controls.running ? s.stopTimer : s.startTimer,
                        ),
                      ),
                      if (!controls.running)
                        OutlinedButton.icon(
                          onPressed: widget.timer.reset,
                          icon: const Icon(Icons.restart_alt),
                          label: Text(s.resetTimer),
                        ),
                    ],
                  ),
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
                ValueListenableBuilder(
                  valueListenable: _controls,
                  builder: (context, controls, _) => controls.running
                      ? const SizedBox.shrink()
                      : Text(s.pressureGuideInstructions),
                ),
                const SizedBox(height: 20),
                ListenableBuilder(
                  listenable: _updates,
                  child: Text(s.pressureGuideMarkers),
                  builder: (context, markers) => _readouts(context, markers!),
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

  Widget _readouts(BuildContext context, Widget markers) {
    final s = AppLocalizations.of(context);
    final elapsed = _elapsed;
    final target = widget.guide.targetAt(elapsed);
    final next = widget.guide.targetAt(elapsed + 2000);
    final done = elapsed > widget.guide.endMs;
    final actual = (widget.session?.sensor.connected ?? false) ? _actual : null;
    final number = NumberFormat(
      '0.0',
      Localizations.localeOf(context).toString(),
    );
    String bar(double? value) => value == null ? '—' : number.format(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (done) Text(s.pressureGuideComplete),
        PressureReadouts(target: bar(target), actual: bar(actual)),
        const SizedBox(height: 12),
        Text('${s.pressureGuideAhead}: ${bar(next)} bar'),
        PressureGuideChart(
          guide: widget.guide,
          elapsedMs: elapsed,
          actual: widget.timer.running ? actual : null,
          trace: widget.session?.trace.points ?? const [],
        ),
        markers,
        if (actual == null) Text(s.pressureGuideManual),
        if (actual != null && target != null)
          Text(s.pressureGuideDifference(number.format(actual - target))),
      ],
    );
  }
}
