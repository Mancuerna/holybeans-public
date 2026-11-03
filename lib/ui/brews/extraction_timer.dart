import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

/// Extraction time as minutes and seconds fields with a stopwatch that
/// writes into them, a reset and, while running, a button that copies the
/// elapsed seconds into a phase field (bloom or pre-infusion).
class ExtractionTimerField extends StatefulWidget {
  const ExtractionTimerField({
    super.key,
    required this.timer,
    this.previousDuration,
    this.marks = const [],
    this.actions = const [],
    this.showToggle = true,
  });

  final BrewTimer timer;

  /// Helper text with the previous brew's time, when repeating.
  final String? previousDuration;

  /// Moments to mark while the timer runs, such as the end of the bloom:
  /// each button writes the elapsed seconds into its field.
  final List<({TextEditingController field, String label})> marks;

  /// Extra buttons before the start button, such as "Wait for drip".
  final List<Widget> actions;

  /// Whether the start and stop button shows here; with a scale it lives
  /// on the weight chart instead.
  final bool showToggle;

  @override
  State<ExtractionTimerField> createState() => _ExtractionTimerFieldState();
}

class _ExtractionTimerFieldState extends State<ExtractionTimerField> {
  final _minutesKey = GlobalKey<FormFieldState<String>>();
  final _secondsKey = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    widget.timer.onValidateStart = _validateStart;
  }

  @override
  void didUpdateWidget(ExtractionTimerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timer == widget.timer) return;
    oldWidget.timer.onValidateStart = null;
    widget.timer.onValidateStart = _validateStart;
  }

  void _validateStart() {
    _minutesKey.currentState?.validate();
    _secondsKey.currentState?.validate();
    if (!widget.timer.hasValidDuration && mounted) {
      Scrollable.ensureVisible(context, alignment: .5);
    }
  }

  String? _validate(String? value, {int? maximum}) =>
      isValidBrewDurationPart(value, maximum: maximum)
      ? null
      : AppLocalizations.of(context)!.invalidDuration;

  @override
  void dispose() {
    if (widget.timer.onValidateStart == _validateStart) {
      widget.timer.onValidateStart = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final timer = widget.timer;
    return ListenableBuilder(
      listenable: timer,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                s.extractionDuration,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  ...widget.actions,
                  if (timer.running)
                    for (final (index, mark) in widget.marks.indexed)
                      TextButton(
                        key: ValueKey(
                          index == 0
                              ? 'extraction-timer-mark'
                              : 'extraction-timer-mark-$index',
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          mark.field.text = '${timer.elapsedSeconds}';
                        },
                        child: Text(mark.label),
                      ),
                  if (timer.running ||
                      timer.minutes.text.isNotEmpty ||
                      timer.seconds.text.isNotEmpty)
                    IconButton(
                      key: const ValueKey('extraction-timer-reset'),
                      tooltip: s.resetTimer,
                      onPressed: timer.reset,
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  if (widget.showToggle)
                    FilledButton.tonalIcon(
                      key: const ValueKey('extraction-timer'),
                      // Felt, for a press made without looking.
                      onPressed: !timer.running && !timer.canStart
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              timer.toggle();
                            },
                      icon: Icon(
                        timer.running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(timer.running ? s.stopTimer : s.startTimer),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: _minutesKey,
                  controller: timer.minutes,
                  readOnly: timer.running,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: s.durationMinutes,
                    helperText: widget.previousDuration,
                    counterText: '',
                  ),
                  validator: _validate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: _secondsKey,
                  controller: timer.seconds,
                  readOnly: timer.running,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  decoration: InputDecoration(
                    labelText: s.durationSeconds,
                    counterText: '',
                  ),
                  validator: (value) => _validate(value, maximum: 59),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
