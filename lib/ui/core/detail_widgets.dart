import 'package:flutter/material.dart';
import 'package:holybeans/domain/flavor_descriptors.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/flavor_note_chip.dart';
import 'package:holybeans/ui/core/flavor_note_labels.dart';
import 'package:holybeans/ui/core/semantic_colors.dart';
import 'package:intl/intl.dart';

/// One value in a [StatGrid], e.g. "Dose" / "18 g".
class StatItem {
  const StatItem(
    this.label,
    this.value, {
    this.caption,
    this.key,
    this.frozen = false,
  });

  final String label;
  final String value;
  final String? caption;
  final Key? key;
  final bool frozen;
}

/// Dense grid of labelled values used by detail sheets.
///
/// Uses three columns on phones and falls back to two when the text is
/// enlarged, so values keep a readable width.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.items, this.minimumTileWidth});

  final List<StatItem> items;
  final double? minimumTileWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    const gap = 12.0;
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 15;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            largeText ||
                constraints.maxWidth < 300 ||
                (minimumTileWidth != null &&
                    (constraints.maxWidth - gap * 2) / 3 < minimumTileWidth!)
            ? 2
            : 3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 4,
          children: [
            for (final item in items)
              SizedBox(
                key: item.key,
                width: width,
                child: _StatTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

/// Text that wraps between words but never splits one: when its longest
/// word is wider than the space (a long word with large system text or a
/// wide system font), the whole text shrinks just enough to fit it.
class WordSafeText extends StatelessWidget {
  const WordSafeText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final words = text.split(RegExp(r'\s+'));
      final direction = Directionality.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      double longestAt(TextStyle style) {
        var longest = 0.0;
        for (final word in words) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textScaler: scaler,
            textDirection: direction,
            maxLines: 1,
          )..layout();
          if (painter.width > longest) longest = painter.width;
          painter.dispose();
        }
        return longest;
      }

      // Android scales large text non-linearly, so shrink and measure
      // again until the longest word fits.
      final room = constraints.maxWidth;
      var fitted = style;
      var longest = longestAt(fitted);
      for (var tries = 0; longest > room && tries < 4; tries++) {
        fitted = fitted.copyWith(
          fontSize: (fitted.fontSize ?? 14) * room / longest * 0.99,
        );
        longest = longestAt(fitted);
      }
      return Text(text, style: fitted);
    },
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      label: [
        item.label,
        item.value,
        if (item.caption != null) item.caption!,
      ].join(', '),
      excludeSemantics: true,
      // A ruled cell, like a lab sheet's: the figures carry the weight.
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WordSafeText(
                item.label,
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  item.value,
                  maxLines: 1,
                  style: AppTheme.figures(
                    theme.textTheme.headlineSmall,
                  ).copyWith(color: item.frozen ? frozenColor(context) : null),
                ),
              ),
              if (item.caption != null)
                Text(
                  item.caption!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title block for detail sheets: compact secondary actions, the item
/// name and an optional subtitle. The sheet itself says what it is, so no
/// label sits above the name.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The actions get a row of their own, so the title, often a long
        // coffee name, has the whole width.
        if (actions.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Small star badge for 0–10 ratings on cards.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.rating,
    required this.localeName,
    required this.semanticLabel,
  });

  final double rating;
  final String localeName;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 2),
          Text(
            NumberFormat('0.#', localeName).format(rating),
            style: AppTheme.figures(theme.textTheme.titleLarge)
                .copyWith(color: colors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Grams with at most one decimal, e.g. "18 g" or "17,5 g".
/// Grams with one decimal at most and the language's grouping, so large
/// totals read the same everywhere ("1,466.3 g", "14.839 g").
String formatGrams(double grams, String localeName) =>
    '${NumberFormat('#,##0.#', localeName).format(grams)} g';

/// Tasting notes from a comma-separated flavour profile, as small chips.
class FlavorNotes extends StatelessWidget {
  const FlavorNotes({super.key, required this.profile, this.maxNotes});

  final String profile;

  /// Shows at most this many notes followed by "+N", when set.
  final int? maxNotes;

  static List<String> split(String profile) => splitFlavorNotes(profile);

  @override
  Widget build(BuildContext context) {
    final notes = split(profile);
    final shown = maxNotes == null ? notes : notes.take(maxNotes!).toList();
    final hidden = notes.length - shown.length;
    final s = AppLocalizations.of(context)!;
    return Semantics(
      label: notes.map((note) => flavorNoteLabel(note, s)).join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final note in shown) FlavorNoteChip(note: note),
          if (hidden > 0) FlavorNoteChip(note: '+$hidden'),
        ],
      ),
    );
  }
}

/// "Just now", "12 min ago", "3 h ago", "Yesterday" or "4 days ago".
String relativeTime(AppLocalizations s, DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return s.justNow;
  if (elapsed.inHours < 1) return s.minutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return s.hoursAgo(elapsed.inHours);
  return s.daysAgo(elapsed.inDays);
}

/// [relativeTime] inside a sentence, after a comma: "Meticulous, 2 days
/// ago" rather than "…, Hace 2 días".
String relativeTimeInline(AppLocalizations s, DateTime time, DateTime now) {
  final text = relativeTime(s, time, now);
  return text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}

/// A duration in days, or in whole weeks from two weeks on; zero is today.
String dayOrWeekSpan(AppLocalizations s, int days) => days == 0
    ? s.today
    : days >= 14
    ? s.weeksCount(days ~/ 7)
    : s.daysCount(days);

/// Scrollable padded body of a details bottom sheet.
class DetailSheetContent extends StatelessWidget {
  const DetailSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: child,
        ),
      ),
    ),
  );
}

/// A labelled value: side by side on wide screens, stacked when narrow,
/// with large text or when [stacked] (e.g. long notes).
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.stacked = false});

  final String label;
  final String value;
  final bool stacked;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final labelText = Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
        final valueText = Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: stacked ? null : FontWeight.w600,
          ),
        );
        final largeText = MediaQuery.textScalerOf(context).scale(10) > 15;
        if (stacked || largeText || constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, const SizedBox(height: 2), valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: constraints.maxWidth * 0.4, child: labelText),
            const SizedBox(width: 12),
            Expanded(child: valueText),
          ],
        );
      },
    ),
  );
}
