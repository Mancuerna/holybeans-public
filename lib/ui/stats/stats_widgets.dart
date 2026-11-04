import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// A titled block of the stats page, with an optional note under the
/// title.
class StatsSection extends StatelessWidget {
  const StatsSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// GitHub-style calendar of brews per day for the last weeks that fit, with
/// the current and longest streaks.
class ActivityCalendar extends StatelessWidget {
  const ActivityCalendar({
    super.key,
    required this.brews,
    required this.today,
    this.preparedCounts,
  });

  final List<Brew> brews;
  final DateTime today;
  final Map<DateTime, int>? preparedCounts;

  static const _cell = 14.0;
  static const _gap = 3.0;
  static const _labelWidth = 30.0;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final counts = preparedCounts ?? brewsPerDay(brews);
    final day = statsDay(today);
    final firstWeekday = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    // Row of today's weekday, with Sunday as 0 like firstDayOfWeekIndex.
    final todayRow = (day.weekday % 7 - firstWeekday) % 7;
    final lastWeekStart = day.subtract(Duration(days: todayRow));

    return LayoutBuilder(
      builder: (context, constraints) {
        final weeks = ((constraints.maxWidth - _labelWidth) / (_cell + _gap))
            .floor()
            .clamp(4, 53);
        final firstWeekStart = lastWeekStart.subtract(
          Duration(days: (weeks - 1) * 7),
        );
        var total = 0;
        for (final MapEntry(key: date, value: count) in counts.entries) {
          if (!date.isBefore(firstWeekStart) && !date.isAfter(day)) {
            total += count;
          }
        }
        final summary = s.statsActivitySummary(total, weeks);
        final streaks = [
          s.statsCurrentStreak(currentStreak(counts, today)),
          s.statsLongestStreak(longestStreak(counts)),
        ].join(', ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '$summary. $streaks',
              child: ExcludeSemantics(
                child: _ActivityGrid(
                  firstWeekStart: firstWeekStart,
                  lastWeekStart: lastWeekStart,
                  weeks: weeks,
                  today: day,
                  counts: counts,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  '$summary\n$streaks',
                  key: const ValueKey('stats-activity-summary'),
                  style: theme.textTheme.bodySmall,
                ),
                const ExcludeSemantics(child: _ActivityLegend()),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The calendar itself: month names over the weeks, weekday names down the
/// side and a square per day.
class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({
    required this.firstWeekStart,
    required this.lastWeekStart,
    required this.weeks,
    required this.today,
    required this.counts,
  });

  final DateTime firstWeekStart;
  final DateTime lastWeekStart;
  final int weeks;
  final DateTime today;
  final Map<DateTime, int> counts;

  static const _cell = ActivityCalendar._cell;
  static const _gap = ActivityCalendar._gap;
  static const _labelWidth = ActivityCalendar._labelWidth;
  static const _columnWidth = _cell + _gap;

  bool _monthStartsIn(int week) {
    final start = firstWeekStart.add(Duration(days: week * 7));
    final end = start.add(const Duration(days: 6));
    return start.month != end.month || start.day == 1;
  }

  Widget _day(DateTime date) {
    if (date.isAfter(today)) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final count = counts[date] ?? 0;
    return _ActivitySwatch(
      count,
      key: ValueKey('activity-${date.year}-${date.month}-${date.day}-$count'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeName = regionalLocale.toString();
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final dayLabels = DateFormat.E(localeName);
    final monthLabels = DateFormat.MMM(localeName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 16,
          width: _labelWidth + weeks * _columnWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var week = 1; week < weeks; week++)
                if (_monthStartsIn(week))
                  Positioned(
                    left: _labelWidth + week * _columnWidth,
                    child: Text(
                      monthLabels.format(
                        firstWeekStart.add(Duration(days: week * 7 + 6)),
                      ),
                      style: labelStyle,
                    ),
                  ),
            ],
          ),
        ),
        Row(
          key: const ValueKey('stats-activity'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Column(
                children: [
                  for (var row = 0; row < 7; row++)
                    SizedBox(
                      height: _columnWidth,
                      child: row.isOdd
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                dayLabels.format(
                                  lastWeekStart.add(Duration(days: row)),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: labelStyle,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            for (var week = 0; week < weeks; week++)
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: Column(
                  children: [
                    for (var row = 0; row < 7; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _gap),
                        child: _day(
                          firstWeekStart.add(Duration(days: week * 7 + row)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Less" to "more", with the five shades a day can take.
class _ActivityLegend extends StatelessWidget {
  const _ActivityLegend();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.statsLess, style: style),
        const SizedBox(width: 4),
        for (final count in [0, 1, 2, 3, 4]) ...[
          _ActivitySwatch(count),
          const SizedBox(width: 2),
        ],
        const SizedBox(width: 2),
        Text(s.statsMore, style: style),
      ],
    );
  }
}

/// One day's square, darker the more brews it had.
class _ActivitySwatch extends StatelessWidget {
  const _ActivitySwatch(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: ActivityCalendar._cell,
      height: ActivityCalendar._cell,
      decoration: BoxDecoration(
        color: switch (count) {
          0 => colors.surfaceContainerHighest,
          1 => colors.primary.withValues(alpha: 0.25),
          2 => colors.primary.withValues(alpha: 0.5),
          3 => colors.primary.withValues(alpha: 0.75),
          _ => colors.primary,
        },
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// 3×3 map of brews by extraction compass cell, coloured by how often each
/// cell appears, with the average rating.
class ExtractionMapGrid extends StatelessWidget {
  const ExtractionMapGrid({super.key, required this.cells});

  final Map<(int, int), CompassCellStats> cells;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final most = cells.values.fold(
      0,
      (max, cell) => cell.count > max ? cell.count : max,
    );
    final axis = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    Widget cell(int balance, int strength) {
      final stats = cells[(balance, strength)];
      final count = stats?.count ?? 0;
      final strengthShare = most == 0 ? 0.0 : count / most;
      final background = count == 0
          ? colors.surfaceContainerHigh
          : Color.lerp(colors.primaryContainer, colors.primary, strengthShare)!;
      final foreground = count == 0
          ? colors.onSurfaceVariant
          : strengthShare > 0.5
          ? colors.onPrimary
          : colors.onPrimaryContainer;
      final rating = stats?.averageRating;
      final label = [
        s.statsExtractionCell(compassLabel(s, balance, strength), count),
        if (rating != null) '${number.format(rating)} / 10',
      ].join(', ');
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: Container(
              key: ValueKey('stats-compass-$balance-$strength'),
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count == 0 ? '–' : '$count',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (rating != null)
                    Text(
                      '★ ${number.format(rating)}',
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        ExcludeSemantics(child: Text(s.compassStrong, style: axis)),
        const SizedBox(height: 4),
        Row(
          children: [
            ExcludeSemantics(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(s.compassSour, style: axis),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  for (final strength in [1, 0, -1])
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final balance in [-1, 0, 1])
                            cell(balance, strength),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(s.compassBitter, style: axis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(child: Text(s.compassWeak, style: axis)),
      ],
    );
  }
}

/// Top items as labelled bars scaled to the most used one; [byRating]
/// shows the average rating first for rating rankings.
class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.keyPrefix,
    required this.items,
    this.byRating = false,
  });

  final String keyPrefix;
  final List<RankedItem> items;
  final bool byRating;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final most = items.fold(
      0,
      (max, item) => item.count > max ? item.count : max,
    );
    return Column(
      children: [
        for (final (index, item) in items.indexed)
          Padding(
            key: ValueKey('stats-$keyPrefix-$index'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Wraps the counts below the name when the text is large.
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (item.flag != null)
                            TextSpan(
                              text: '${item.flag}  ',
                              semanticsLabel: '',
                            ),
                          TextSpan(text: item.label),
                        ],
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (byRating && item.averageRating != null)
                          '★ ${number.format(item.averageRating)}',
                        s.brewsCount(item.count),
                        if (!byRating && item.averageRating != null)
                          '★ ${number.format(item.averageRating)}',
                      ].join(', '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: byRating
                          ? (item.averageRating ?? 0) / 10
                          : item.count / most,
                      minHeight: 4,
                      color: colors.onSurfaceVariant,
                      backgroundColor: colors.outlineVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
