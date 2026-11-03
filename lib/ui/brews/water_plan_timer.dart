import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/motion.dart';

class WaterPlanTimer extends StatelessWidget {
  const WaterPlanTimer({
    super.key,
    required this.timer,
    required this.readingKey,
    this.bloom,
  });

  final BrewTimer timer;
  final GlobalKey readingKey;
  final TextEditingController? bloom;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Semantics(
              label: s.extractionDuration,
              child: Text(
                formatDuration(timer.elapsedSeconds),
                key: const ValueKey('water-plan-time'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (timer.running || timer.elapsedSeconds > 0)
                  IconButton(
                    tooltip: s.resetTimer,
                    onPressed: timer.reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                FilledButton.tonalIcon(
                  key: const ValueKey('water-plan-timer-toggle'),
                  onPressed: !timer.running && !timer.canStart
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          HapticFeedback.mediumImpact();
                          timer.toggle();
                          if (!timer.running) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final target = readingKey.currentContext;
                            if (target == null || !target.mounted) return;
                            Scrollable.ensureVisible(
                              target,
                              alignment:
                                  (target.size?.height ?? 0) >
                                      Scrollable.of(target)
                                          .position
                                          .viewportDimension
                                  ? 0
                                  : .5,
                              duration: motionDuration(
                                target,
                                const Duration(milliseconds: 300),
                              ),
                              curve: Curves.easeOut,
                            );
                          });
                        },
                  icon: Icon(
                    timer.running
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(timer.running ? s.stopTimer : s.startTimer),
                ),
              ],
            ),
          ],
        ),
        if (!timer.hasValidDuration)
          Text(
            s.invalidDuration,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (timer.running && bloom != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('water-plan-mark-bloom'),
              onPressed: () {
                HapticFeedback.selectionClick();
                bloom!.text = '${timer.elapsedSeconds}';
              },
              child: Text(s.markBloom),
            ),
          ),
      ],
    );
  }
}
