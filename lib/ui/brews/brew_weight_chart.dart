import 'package:flutter/material.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/espresso_brew_readout.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/filter_brew_readout.dart';
import 'package:holybeans/ui/brews/filter_water_targets.dart';
import 'package:holybeans/ui/brews/weight_targets.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/motion.dart';

/// Recording controls, live curve and progress for the brew being prepared.
class BrewWeightChart extends StatelessWidget {
  const BrewWeightChart({super.key, required this.model});

  final BrewFormModel model;

  @override
  Widget build(BuildContext context) {
    final scale = model.scaleSession;
    if (scale == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([
        scale.scale,
        model.timer,
        model.draft.firstDrip,
        model.draft.dose,
        model.draft.water,
        model.draft.pours,
        if (model.isEspresso && model.pressureSession != null)
          model.pressureSession!.sensor,
      ]),
      builder: (context, _) {
        if (!scale.scale.connected && scale.curve == null) {
          return const SizedBox.shrink();
        }
        final s = AppLocalizations.of(context)!;
        final firstDrip = int.tryParse(model.draft.firstDrip.text);
        final plan =
            !model.isEspresso &&
                model.draft.pours.waterPlanUsed &&
                model.shows(BrewParameter.bloomCount) &&
                model.shows(BrewParameter.pourCount)
            ? model.draft.pours.waterPlan(
                dose: parseNumber(model.draft.dose.text),
                water: model.devices.filterWaterTarget,
              )
            : null;
        return Builder(
          builder: (chartContext) {
            Widget chart(List<WeightTarget> targets) => ExtractionChart(
              key: const ValueKey('scale-live-chart'),
              weightTargets: targets,
              curve: model.devices.curve ?? _emptyWeightCurve,
              flowUnit: 'g/s',
              live: scale.recording,
              height: 180,
              replayable: false,
              showReadout: model.isEspresso,
              showFlowStatistics: model.isEspresso,
              targetWeightGrams:
                  model.isEspresso && model.shows(BrewParameter.ratio)
                  ? model.espressoTargetGrams
                  : null,
              firstDripMs: firstDrip == null ? null : firstDrip * 1000,
              action: model.timerAtWaterPlan
                  ? null
                  : FilledButton.tonalIcon(
                      key: const ValueKey('chart-timer-toggle'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: model.timer.running
                          ? model.timer.stop
                          : !model.timer.canStart
                          ? null
                          : () {
                              model.timer.toggle();
                              if (model.timer.running) {
                                Scrollable.ensureVisible(
                                  chartContext,
                                  alignment: 0.5,
                                  duration: motionDuration(
                                    chartContext,
                                    const Duration(milliseconds: 300),
                                  ),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                      icon: Icon(
                        model.timer.running
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        model.timer.running ? s.stopTimer : s.startTimer,
                      ),
                    ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (plan != null && plan.problem == null)
                  FilterWaterTargets(
                    plan: plan,
                    poured: scale.pouredGrams,
                    builder: chart,
                  )
                else
                  chart(const []),
                if (model.isEspresso) ...[
                  const SizedBox(height: 8),
                  EspressoBrewReadout(
                    grams: scale.beverageGrams,
                    doseGrams: parseNumber(model.draft.dose.text),
                    targetGrams: model.espressoTargetGrams,
                    targetRatio: model.espressoTargetRatio,
                    showRatio: model.shows(BrewParameter.ratio),
                  ),
                ],
                if (!model.isEspresso) ...[
                  const SizedBox(height: 8),
                  FilterBrewReadout(
                    showRatio: model.shows(BrewParameter.ratio),
                    showTarget: model.shows(BrewParameter.water),
                    progress: FilterBrewProgress(
                      pouredGrams: scale.pouredGrams,
                      doseGrams: parseNumber(model.draft.dose.text),
                      targetWaterGrams: model.devices.filterWaterTarget,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

final _emptyWeightCurve = ShotCurve(
  timesMs: const [0],
  flow: const [0],
  weight: const [0],
);
