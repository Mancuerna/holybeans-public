import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/database/journal_write_gate.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/motion.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';
import 'package:holybeans/ui/sync/drive_sync_page.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';

/// Advice for the next brew from the extraction compass.
String? compassAdvice(AppLocalizations s, int? balance, int? strength) {
  if (balance == null || strength == null) return null;
  final advice = [
    if (balance < 0) s.adviceSour,
    if (balance > 0) s.adviceBitter,
    if (strength < 0) s.adviceWeak,
    if (strength > 0) s.adviceStrong,
  ];
  return advice.isEmpty ? s.adviceBalanced : advice.join(' ');
}

String compassLabel(AppLocalizations s, int balance, int strength) {
  final parts = [
    if (strength > 0) s.compassStrong,
    if (strength < 0) s.compassWeak,
    if (balance < 0) s.compassSour,
    if (balance > 0) s.compassBitter,
  ];
  return parts.isEmpty ? s.compassBalanced : parts.join(', ');
}

List<String> flavorScoreLabels(AppLocalizations s) => [
  s.scoreAcidity,
  s.scoreSweetness,
  s.scoreBitterness,
  s.scoreBody,
  s.scoreAftertaste,
];

/// 3×3 grid: sour ↔ bitter across, weak ↔ strong up and down. Tapping the
/// selected cell clears it.
class ExtractionCompass extends StatelessWidget {
  const ExtractionCompass({
    super.key,
    required this.balance,
    required this.strength,
    required this.onChanged,
  });

  final int? balance;
  final int? strength;
  final void Function(int? balance, int? strength) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final axis = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    Widget cell(int b, int st) {
      final selected = balance == b && strength == st;
      return Semantics(
        button: true,
        selected: selected,
        label: compassLabel(s, b, st),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('compass-$b-$st'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => selected ? onChanged(null, null) : onChanged(b, st),
          child: AnimatedContainer(
            duration: motionDuration(
              context,
              const Duration(milliseconds: 150),
            ),
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, color: colors.onPrimary)
                : null,
          ),
        ),
      );
    }

    return Column(
      children: [
        Text(s.compassStrong, style: axis),
        const SizedBox(height: 6),
        Row(
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Text(s.compassSour, style: axis),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Column(
                  children: [
                    for (final st in const [1, 0, -1])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final b in const [-1, 0, 1])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: cell(b, st),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            RotatedBox(
              quarterTurns: 1,
              child: Text(s.compassBitter, style: axis),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(s.compassWeak, style: axis),
      ],
    );
  }
}

/// Five flavour scores (0–5) drawn as a radar.
class FlavorRadar extends StatelessWidget {
  const FlavorRadar({super.key, required this.scores, this.size = 180});

  final List<int?> scores;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final labels = flavorScoreLabels(s);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: [
        for (var i = 0; i < labels.length; i++)
          if (scores[i] != null) '${labels[i]} ${scores[i]}/5',
      ].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('flavor-radar'),
        width: size + 90,
        height: size + 40,
        child: CustomPaint(
          painter: _RadarPainter(
            // A copy, so edits to the caller's list are seen as changes.
            scores: List.of(scores),
            labels: labels,
            grid: colors.outlineVariant,
            fill: colors.primary,
            text: Theme.of(context).textTheme.labelSmall!
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.scores,
    required this.labels,
    required this.grid,
    required this.fill,
    required this.text,
  });

  final List<int?> scores;
  final List<String> labels;
  final Color grid;
  final Color fill;
  final TextStyle text;

  Offset _point(Offset center, double radius, int index, double fraction) {
    final angle = -math.pi / 2 + index * 2 * math.pi / 5;
    return center +
        Offset(math.cos(angle), math.sin(angle)) * radius * fraction;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 4);
    final radius = math.min(size.width - 90, size.height - 40) / 2;
    final gridPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var level = 1; level <= 5; level++) {
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final p = _point(center, radius, i, level / 5);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), gridPaint);
    }
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(center, _point(center, radius, i, 1), gridPaint);
      final painter = TextPainter(
        text: TextSpan(text: labels[i], style: text),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 88);
      final anchor = _point(center, radius + 12, i, 1);
      painter.paint(
        canvas,
        anchor - Offset(painter.width / 2, painter.height / 2),
      );
    }
    if (scores.every((score) => score == null)) return;
    final shape = Path();
    for (var i = 0; i < 5; i++) {
      final p = _point(center, radius, i, (scores[i] ?? 0) / 5);
      i == 0 ? shape.moveTo(p.dx, p.dy) : shape.lineTo(p.dx, p.dy);
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = fill.withValues(alpha: 0.25));
    canvas.drawPath(
      shape,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      !listEquals(old.scores, scores) ||
      !listEquals(old.labels, labels) ||
      old.fill != fill ||
      old.grid != grid;
}

/// One 0–5 score as a row of tappable dots; tapping the current value
/// clears it.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label)),
        for (var score = 0; score <= 5; score++)
          Semantics(
            button: true,
            selected: value == score,
            label: '$label $score/5',
            excludeSemantics: true,
            child: InkResponse(
              key: ValueKey('score-$label-$score'),
              radius: 22,
              onTap: () => onChanged(value == score ? null : score),
              child: SizedBox(
                width: 36,
                height: 44,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value != null && score <= value!
                          ? colors.primary
                          : colors.surfaceContainerHigh,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Center(
                      child: Text(
                        '$score',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: value != null && score <= value!
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Rates a brew after the fact: rating, notes, compass and cup profile.
Future<bool?> showRateBrewSheet(
  BuildContext context,
  JournalRepository repository,
  Brew brew, {
  required String title,
}) => showFormSheet(
  context,
  _RateBrewSheet(repository: repository, brew: brew, title: title),
  useSafeArea: true,
);

class _RateBrewSheet extends StatefulWidget {
  const _RateBrewSheet({
    required this.repository,
    required this.brew,
    required this.title,
  });

  final JournalRepository repository;
  final Brew brew;
  final String title;

  @override
  State<_RateBrewSheet> createState() => _RateBrewSheetState();
}

class _RateBrewSheetState extends State<_RateBrewSheet> {
  late double? rating = widget.brew.rating;
  late final notes = TextEditingController(text: widget.brew.notes);
  late int? balance = widget.brew.tasteBalance;
  late int? strength = widget.brew.tasteStrength;
  late final List<int?> scores = BrewTasting.of(widget.brew).scores;
  bool saving = false;
  String? saveError;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    final sync = DriveSyncScope.maybeOf(context);
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      if (sync != null) await waitForDriveCheck(sync);
      // Cancel/Back remains available during the wait and must cancel saving.
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      await widget.repository.rateBrew(
        widget.brew.id,
        rating: rating,
        notes: notes.text,
        tasting: BrewTasting(
          balance: balance,
          strength: strength,
          acidity: scores[0],
          sweetness: scores[1],
          bitterness: scores[2],
          body: scores[3],
          aftertaste: scores[4],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error, stack) {
      reportError(error, stack);
      if (!mounted) return;
      final s = AppLocalizations.of(context)!;
      setState(() {
        saving = false;
        saveError =
            error is JournalReadOnlyException || error is TimeoutException
            ? '${sync == null ? s.driveSyncChecking : driveStatusLabel(s, sync)} ${s.ratingSaveRetry}'
            : s.ratingSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final advice = compassAdvice(s, balance, strength);
    final section = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              key: const ValueKey('rate-brew-sheet'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text(
                  s.rateBrew,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(widget.title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                OptionalRatingSlider(
                  value: rating,
                  onChanged: (value) => setState(() => rating = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.notes),
                ),
                const SizedBox(height: 20),
                Text(s.extractionCompass, style: section),
                Text(s.compassHint, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                ExtractionCompass(
                  balance: balance,
                  strength: strength,
                  onChanged: (b, st) => setState(() {
                    balance = b;
                    strength = st;
                  }),
                ),
                if (advice != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: const ValueKey('compass-advice'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(advice)),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(s.flavorScores, style: section),
                const SizedBox(height: 8),
                Center(child: FlavorRadar(scores: scores, size: 150)),
                for (final (index, label) in flavorScoreLabels(s).indexed)
                  _ScoreRow(
                    label: label,
                    value: scores[index],
                    onChanged: (value) => setState(() => scores[index] = value),
                  ),
              ],
            ),
          ),
          if (saveError != null || saving)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  saveError ??
                      (DriveSyncScope.maybeOf(context)?.applying == true
                          ? s.ratingWaitingForDrive
                          : s.ratingSaving),
                  key: const ValueKey('rate-brew-status'),
                  style: TextStyle(
                    color: saveError == null ? null : theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('rate-brew-save'),
                      onPressed: saving ? null : _save,
                      child: Text(s.save),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
