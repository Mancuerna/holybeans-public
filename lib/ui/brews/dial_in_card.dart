import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/motion.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// The previous brew of the same coffee and method: recipe, result and, when
/// it was rated with the compass, what to change next time. With a
/// favourite recipe, that is the base, and the last brew is only a note.
/// The brew's notes and those of the newest one, often written for the next
/// brew, follow in two lines each, with the rest behind "Show more".
class DialInCard extends StatelessWidget {
  const DialInCard({
    super.key,
    required this.brew,
    required this.rated,
    this.favorite = false,
    this.latest,
    this.newest,
    this.editingId,
  });

  final Brew brew;

  /// Whether [brew] is the last rated one rather than simply the last.
  final bool rated;

  /// Whether [brew] is the favourite recipe of this coffee and method.
  final bool favorite;

  /// Beside a favourite, the last brew when it is another one.
  final Brew? latest;

  /// The latest brew of the coffee and method, rated or not.
  final Brew? newest;

  /// The brew being edited, whose notes are already in the form.
  final String? editingId;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final time = brew.timeSeconds;
    final recipe = [
      if (brew.isPreGround)
        s.preGround
      else if (brew.grindSetting?.trim() case final grind?
          when grind.isNotEmpty)
        grind,
      if (brew.doseGrams != null)
        [
          '${number.format(brew.doseGrams)} g',
          if (brew.waterGrams ?? brew.beverageGrams case final out?)
            '${number.format(out)} g',
        ].join(' → '),
      if (time != null) formatDuration(time),
      if (brew.temperatureC != null) '${number.format(brew.temperatureC)} °C',
    ].join(', ');
    String resultOf(Brew brew) => [
      if (brew.rating != null) '★ ${number.format(brew.rating)}',
      if ((brew.tasteBalance, brew.tasteStrength) case (
        final balance?,
        final strength?,
      ))
        compassLabel(s, balance, strength),
    ].join(', ');
    final result = resultOf(brew);
    // The advice is about changing the brew it judges; a favourite is
    // where to start from, not something to fix.
    final advice = favorite
        ? null
        : compassAdvice(s, brew.tasteBalance, brew.tasteStrength);
    final latestResult = latest == null ? '' : resultOf(latest!);
    String? noteOf(Brew? row) {
      if (row == null || row.id == editingId) return null;
      final text = row.notes?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    final note = noteOf(brew);
    final newestNote = newest?.id == brew.id ? null : noteOf(newest);
    final title = favorite
        ? s.dialInFavoriteTitle
        : rated
        ? s.dialInRatedTitle
        : s.dialInTitle;
    return Card(
      key: const ValueKey('brew-dial-in'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  favorite ? Icons.favorite_rounded : Icons.tune_rounded,
                  size: 18,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$title, ${relativeTimeInline(s, DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs), DateTime.now())}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (recipe.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                recipe,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
            if (result.isNotEmpty)
              Text(
                result,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (latestResult.isNotEmpty)
              Text(
                latest?.id == newest?.id
                    ? s.dialInLatestNote(latestResult)
                    : s.dialInLatestRatedNote(latestResult),
                key: const ValueKey('brew-dial-in-latest'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            if (advice != null) ...[
              const SizedBox(height: 4),
              Text(
                advice,
                key: const ValueKey('brew-dial-in-advice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 6),
              DialInNote(
                key: const ValueKey('brew-dial-in-note'),
                label: s.dialInNote,
                text: note,
              ),
            ],
            if (newestNote != null) ...[
              const SizedBox(height: 6),
              DialInNote(
                key: const ValueKey('brew-dial-in-newest-note'),
                label: s.dialInNewestNote,
                text: newestNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A brew's notes on the help card, labelled: two lines, and the rest a tap
/// away ("Show more"), so a long note does not stretch the card.
class DialInNote extends StatefulWidget {
  const DialInNote({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  State<DialInNote> createState() => _DialInNoteState();
}

class _DialInNoteState extends State<DialInNote> {
  static const _lines = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    final style = theme.textTheme.bodyMedium?.copyWith(color: color);
    final span = TextSpan(
      children: [
        TextSpan(
          text: '${widget.label}: ',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(
          text: widget.text,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(style: style, children: [span]),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        final text = AnimatedSize(
          duration: motionDuration(context, const Duration(milliseconds: 180)),
          alignment: Alignment.topCenter,
          child: Text.rich(
            span,
            style: style,
            maxLines: _expanded ? null : _lines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
        );
        if (!long) return text;
        // The whole note opens and closes, a larger target than its link.
        return InkWell(
          key: const ValueKey('brew-dial-in-note-more'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _expanded ? s.showLess : s.showMore,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
