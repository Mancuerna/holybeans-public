import 'package:flutter/material.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_ratio_slider.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_chart.dart';
import 'package:holybeans/ui/brews/pour_assistant/pour_run.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/scale/scale_readout.dart';
import 'package:intl/intl.dart';

/// What the assistant hands back to the brew: the plan followed, how long
/// the brew took and, with a scale, its weight curve and the water poured.
class PourAssistantResult {
  const PourAssistantResult({
    required this.plan,
    required this.totalSeconds,
    this.curve,
    this.pouredGrams,
  });

  final PourPlan plan;
  final int totalSeconds;
  final ShotCurve? curve;
  final double? pouredGrams;
}

/// Opens the pour assistant on [plan]; returns the result when the brew is
/// finished, or null when left before.
Future<PourAssistantResult?> showPourAssistant(
  BuildContext context, {
  required PourPlan plan,
  DeviceFeedback feedback = const DeviceFeedback(),
  Scale? scale,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) =>
        PourAssistantPage(plan: plan, feedback: feedback, scale: scale),
  ),
);

/// Sets up a pour plan (dose, ratio, blooms and pours) and then follows it.
/// With a paired [scale], it follows the weight too.
class PourAssistantPage extends StatefulWidget {
  const PourAssistantPage({
    super.key,
    required this.plan,
    this.feedback = const DeviceFeedback(),
    this.stopwatch = Stopwatch.new,
    this.scale,
  });

  final PourPlan plan;
  final DeviceFeedback feedback;
  final Stopwatch Function() stopwatch;
  final Scale? scale;

  @override
  State<PourAssistantPage> createState() => _PourAssistantPageState();
}

class _PourAssistantPageState extends State<PourAssistantPage> {
  late PourPlan plan = widget.plan;
  bool running = false;
  bool atYourPace = false;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final page = Scaffold(
      appBar: AppBar(title: Text(s.pourAssistant)),
      body: SafeArea(
        child: running
            ? PourRunView(
                plan: plan,
                atYourPace: atYourPace,
                feedback: widget.feedback,
                stopwatch: widget.stopwatch,
                scale: widget.scale,
                onFinish: (seconds, {curve, pouredGrams}) => Navigator.pop(
                  context,
                  PourAssistantResult(
                    plan: plan,
                    totalSeconds: seconds,
                    curve: curve,
                    pouredGrams: pouredGrams,
                  ),
                ),
              )
            : _PlanEditor(
                plan: plan,
                atYourPace: atYourPace,
                onPaceChanged: (value) => setState(() => atYourPace = value),
                scale: widget.scale,
                onChanged: (value) => setState(() => plan = value),
                onStart: () => setState(() => running = true),
              ),
      ),
    );
    return FormExitGuard(
      hasChanges: () => running,
      busy: () => false,
      child: page,
    );
  }
}

class _PlanEditor extends StatefulWidget {
  const _PlanEditor({
    required this.plan,
    required this.scale,
    required this.onChanged,
    required this.onStart,
    required this.atYourPace,
    required this.onPaceChanged,
  });

  final PourPlan plan;
  final Scale? scale;
  final ValueChanged<PourPlan> onChanged;
  final VoidCallback onStart;
  final bool atYourPace;
  final ValueChanged<bool> onPaceChanged;

  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  NumberFormat get _plain => NumberFormat('0.#', regionalLocale.toString());
  late final dose = TextEditingController(
    text: _plain.format(widget.plan.doseGrams),
  );
  late final ratio = TextEditingController(
    text: _plain.format(widget.plan.ratio),
  );
  late final List<(TextEditingController, TextEditingController)> blooms = [
    for (final bloom in widget.plan.blooms)
      (
        TextEditingController(
          text: _plain.format(bloom.doseMultiple * widget.plan.doseGrams),
        ),
        TextEditingController(text: '${bloom.waitSeconds}'),
      ),
  ];
  late final _initialNumbers = <TextEditingController, double>{
    dose: widget.plan.doseGrams,
    ratio: widget.plan.ratio,
    for (final (index, bloom) in widget.plan.blooms.indexed)
      blooms[index].$1: bloom.doseMultiple * widget.plan.doseGrams,
  };

  double? _numberValue(TextEditingController controller) =>
      _initialNumbers[controller] ?? parseNumber(controller.text);

  late int pours = widget.plan.pours;
  late final interval = TextEditingController(
    text: '${widget.plan.pourIntervalSeconds}',
  );

  @override
  void dispose() {
    for (final controller in [
      dose,
      ratio,
      interval,
      for (final (water, wait) in blooms) ...[water, wait],
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The plan as typed; blooms are kept relative to the dose.
  void _update() {
    final grams = _numberValue(dose) ?? 0;
    widget.onChanged(
      PourPlan(
        doseGrams: grams,
        ratio: _numberValue(ratio) ?? 0,
        blooms: [
          for (final (water, wait) in blooms)
            BloomStep(
              doseMultiple: grams <= 0 ? 0 : (_numberValue(water) ?? 0) / grams,
              waitSeconds: int.tryParse(wait.text.trim()) ?? 0,
            ),
        ],
        pours: pours,
        pourIntervalSeconds: int.tryParse(interval.text.trim()) ?? 0,
      ),
    );
  }

  void _addBloom() {
    final grams = _numberValue(dose) ?? 15;
    final water = TextEditingController(text: _plain.format(grams * 2));
    _initialNumbers[water] = grams * 2;
    setState(() => blooms.add((water, TextEditingController(text: '30'))));
    _update();
  }

  void _removeBloom(int index) {
    _initialNumbers.remove(blooms[index].$1);
    final (water, wait) = blooms.removeAt(index);
    water.dispose();
    wait.dispose();
    setState(() {});
    _update();
  }

  String _problem(AppLocalizations s, PourPlanProblem problem) =>
      switch (problem) {
        PourPlanProblem.dose => s.pourProblemDose,
        PourPlanProblem.ratio => s.pourProblemRatio,
        PourPlanProblem.bloom => s.pourProblemBloom,
        PourPlanProblem.pours => s.pourProblemPours,
        PourPlanProblem.bloomWater => s.pourProblemBloomWater,
      };

  Widget _number(
    TextEditingController controller,
    String label, {
    Key? key,
    String? helper,
    bool decimal = true,
  }) => TextField(
    key: key,
    controller: controller,
    inputFormatters: [decimalInputFormatter],
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    decoration: InputDecoration(labelText: label, helperText: helper),
    onChanged: (_) {
      _initialNumbers.remove(controller);
      _update();
    },
  );

  /// Each bloom's water and wait, and the button to add another.
  List<Widget> _bloomRows(AppLocalizations s, NumberFormat number) => [
    for (final (index, (water, wait)) in blooms.indexed) ...[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _number(
              water,
              '${s.bloomNumber(index + 1)} (g)',
              key: ValueKey('pour-bloom-water-$index'),
              helper: switch ((
                parseNumber(water.text),
                parseNumber(dose.text),
              )) {
                (final grams?, final doseGrams?) when doseGrams > 0 =>
                  s.bloomShare(number.format(grams / doseGrams)),
                _ => null,
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _number(
              wait,
              s.bloomWait,
              key: ValueKey('pour-bloom-wait-$index'),
              decimal: false,
            ),
          ),
          IconButton(
            key: ValueKey('pour-remove-bloom-$index'),
            tooltip: s.removeBloom,
            // Explicitly support recipes without a bloom.
            onPressed: blooms.length > PourPlan.minBlooms
                ? () => _removeBloom(index)
                : null,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
    if (blooms.length < PourPlan.maxBlooms)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('pour-add-bloom'),
          onPressed: _addBloom,
          icon: const Icon(Icons.add_rounded),
          label: Text(s.addBloom),
        ),
      ),
  ];

  /// How many pours, with − and +, and the interval between them.
  Widget _pourCountRow(AppLocalizations s, ThemeData theme) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(s.pourCount, style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: s.fewerPours,
            onPressed: pours > 1
                ? () {
                    setState(() => pours--);
                    _update();
                  }
                : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          Text(
            '$pours',
            key: const ValueKey('pour-count'),
            style: theme.textTheme.titleLarge,
          ),
          IconButton(
            tooltip: s.morePours,
            onPressed: pours < PourPlan.maxPours
                ? () {
                    setState(() => pours++);
                    _update();
                  }
                : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _number(
        interval,
        s.pourInterval,
        key: const ValueKey('pour-interval'),
        decimal: false,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = widget.plan;
    final problem = plan.problem;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final firstPour = problem == null
        ? plan.steps.firstWhere((step) => step.kind == PourStepKind.pour)
        : null;
    String clock(int seconds) => formatDuration(seconds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          s.pourAssistantHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _number(
                dose,
                '${s.dose} (g)',
                key: const ValueKey('pour-dose'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _number(
                ratio,
                '${s.ratio} (1:x)',
                key: const ValueKey('pour-ratio'),
              ),
            ),
          ],
        ),
        BrewRatioSlider(
          espresso: false,
          doseGrams: plan.doseGrams,
          ratio: plan.ratio,
          onChanged: (value) {
            _initialNumbers.remove(ratio);
            ratio.text = _plain.format(value);
            _update();
          },
        ),
        if (problem == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              s.totalWater(number.format(plan.totalWaterGrams)),
              style: theme.textTheme.titleMedium,
            ),
          ),
        const SizedBox(height: 16),
        ..._bloomRows(s, number),
        const SizedBox(height: 8),
        _pourCountRow(s, theme),
        const SizedBox(height: 12),
        if (problem != null)
          Text(
            _problem(s, problem),
            key: const ValueKey('pour-problem'),
            style: TextStyle(color: theme.colorScheme.error),
          )
        else ...[
          Text(
            widget.atYourPace
                ? s.pourManualSummary(
                    plan.pours,
                    number.format(firstPour!.addGrams),
                  )
                : s.pourSummary(
                    plan.pours,
                    number.format(firstPour!.addGrams),
                    clock(plan.pouringEndSecond),
                  ),
            key: const ValueKey('pour-summary'),
          ),
          const SizedBox(height: 12),
          if (!widget.atYourPace) PourChart(plan: plan),
        ],
        if (widget.scale case final scale? when scale.name != null) ...[
          const SizedBox(height: 16),
          ScaleReadout(scale: scale, footer: s.pourScaleHint),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('pour-mode-timed'),
              label: Text(s.pourModeTimed),
              selected: !widget.atYourPace,
              onSelected: (_) => widget.onPaceChanged(false),
            ),
            ChoiceChip(
              key: const ValueKey('pour-mode-manual'),
              label: Text(s.pourModeManual),
              selected: widget.atYourPace,
              onSelected: (_) => widget.onPaceChanged(true),
            ),
          ],
        ),
        Text(widget.atYourPace ? s.pourManualHint : s.pourTimedHint),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('pour-start'),
          onPressed: problem == null ? widget.onStart : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(s.startPouring),
        ),
      ],
    );
  }
}
