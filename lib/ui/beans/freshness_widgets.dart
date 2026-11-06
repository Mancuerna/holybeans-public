import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_help.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart' hide TextDirection;

String freshnessPhaseLabel(AppLocalizations s, FreshnessPhase phase) =>
    switch (phase) {
      FreshnessPhase.degassing => s.phaseDegassing,
      FreshnessPhase.prime => s.phasePrime,
      FreshnessPhase.good => s.phaseGood,
      FreshnessPhase.aging => s.phaseAging,
      FreshnessPhase.stale => s.phaseStale,
    };

String brewStyleLabel(AppLocalizations s, BrewStyle style) =>
    style == BrewStyle.espresso ? s.styleEspresso : s.styleFilter;

Color freshnessPhaseColor(BuildContext context, FreshnessPhase phase) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (phase) {
    FreshnessPhase.degassing =>
      dark ? const Color(0xFFCDB2EB) : const Color(0xFF6D4C91),
    FreshnessPhase.prime =>
      dark ? const Color(0xFFA9D18E) : const Color(0xFF38622F),
    FreshnessPhase.good =>
      dark ? const Color(0xFF8CCFC0) : const Color(0xFF216359),
    FreshnessPhase.aging =>
      dark ? const Color(0xFFFFC078) : const Color(0xFF8A4700),
    FreshnessPhase.stale =>
      dark ? const Color(0xFFBBB5AE) : const Color(0xFF625D58),
  };
}

String? freshnessTimeLabel(
  AppLocalizations s,
  FreshnessWindow window,
  int day,
) {
  final days = window.daysLeftInPhase(day);
  if (days == null) return null;
  return switch (window.phaseAt(day)) {
    FreshnessPhase.degassing => s.freshnessReadyIn(days),
    FreshnessPhase.prime => s.freshnessPrimeRemaining(days),
    FreshnessPhase.good => s.freshnessGoodRemaining(days),
    FreshnessPhase.aging => s.freshnessStaleIn(days),
    FreshnessPhase.stale => null,
  };
}

/// Freshness section of a bean's details: a timeline per brew style, the
/// basis of the windows and the personal sweet spot when there is one.
class FreshnessSection extends StatelessWidget {
  const FreshnessSection({super.key, required this.freshness});

  final CoffeeFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('freshness-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  s.freshness,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: s.freshnessHelpTitle,
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => const FreshnessHelp(),
              ),
            ),
          ],
        ),
        if (freshness.restDays case final days?)
          Container(
            key: const ValueKey('freshness-roaster-rest'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.freshnessBasisRest(days),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(s.freshnessRestExplanation, style: muted),
              ],
            ),
          ),
        for (final style in BrewStyle.values)
          _FreshnessRow(
            style: style,
            day: freshness.day,
            window: freshness.windows[style]!,
          ),
        const _FreshnessLegend(),
        const SizedBox(height: 12),
        Text(
          [
            s.freshnessDay(freshness.day),
            if (freshness.restDays == null) s.freshnessBasisRoast,
            if (freshness.pausedDays > 0)
              s.freshnessPaused(freshness.pausedDays),
            if (freshness.openedDays case final days?) s.freshnessOpened(days),
          ].join('. '),
          style: muted,
        ),
        if (freshness.ratedDays.length >= 2) ...[
          const SizedBox(height: 14),
          _RatingByAgeChart(freshness: freshness),
        ],
        for (final entry in freshness.sweetSpots.entries) ...[
          const SizedBox(height: 10),
          Row(
            key: ValueKey('sweet-spot-${entry.key.name}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.track_changes_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${s.sweetSpot}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: s.sweetSpotValue(
                          brewStyleLabel(s, entry.key),
                          entry.value.startDay,
                          entry.value.endDay,
                          NumberFormat(
                            '0.#',
                            regionalLocale.toString(),
                          ).format(entry.value.averageRating),
                          entry.value.brewCount,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FreshnessRow extends StatelessWidget {
  const _FreshnessRow({
    required this.style,
    required this.day,
    required this.window,
  });

  final BrewStyle style;
  final int day;
  final FreshnessWindow window;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phase = window.phaseAt(day);
    final timing = freshnessTimeLabel(s, window, day);
    final label = [
      brewStyleLabel(s, style),
      freshnessPhaseLabel(s, phase),
      ?timing,
    ].join(', ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('freshness-${style.name}'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      style == BrewStyle.espresso
                          ? Icons.coffee_rounded
                          : Icons.water_drop_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      brewStyleLabel(s, style),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                FreshnessPhaseChip(phase: phase),
                if (timing != null)
                  Text(
                    timing,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FreshnessBar(day: day, window: window, showToday: true),
          ],
        ),
      ),
    );
  }
}

/// A freshness phase as a tinted label in its colour.
class FreshnessPhaseChip extends StatelessWidget {
  const FreshnessPhaseChip({super.key, required this.phase});

  final FreshnessPhase phase;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final color = freshnessPhaseColor(context, phase);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          freshnessPhaseLabel(s, phase),
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _FreshnessLegend extends StatelessWidget {
  const _FreshnessLegend();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final phase in FreshnessPhase.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: freshnessPhaseColor(context, phase),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  freshnessPhaseLabel(s, phase),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class FreshnessBar extends StatelessWidget {
  const FreshnessBar({
    super.key,
    required this.day,
    required this.window,
    this.showToday = false,
  });

  final int day;
  final FreshnessWindow window;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final segments = [
      (window.primeStart, FreshnessPhase.degassing),
      (window.primeEnd - window.primeStart + 1, FreshnessPhase.prime),
      (window.goodUntil - window.primeEnd, FreshnessPhase.good),
      (window.agingUntil - window.goodUntil, FreshnessPhase.aging),
      ((window.agingUntil * 0.15).ceil(), FreshnessPhase.stale),
    ];
    final total = segments.fold<int>(0, (sum, segment) => sum + segment.$1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 14) return const SizedBox(height: 14);
        final marker = ((day + 0.5).clamp(0, total) / total * width).clamp(
          7.0,
          width - 7,
        );
        final bar = SizedBox(
          height: 14,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    for (final (index, (length, phase)) in segments.indexed)
                      Expanded(
                        flex: length < 1 ? 1 : length,
                        child: Container(
                          height: phase == window.phaseAt(day) ? 10 : 6,
                          margin: EdgeInsets.only(
                            right: index == segments.length - 1 ? 0 : 2,
                          ),
                          decoration: BoxDecoration(
                            color: freshnessPhaseColor(context, phase),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: marker - 7,
                top: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.onSurface, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
        if (!showToday) return bar;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment(marker / width * 2 - 1, 0),
              child: Text(
                AppLocalizations.of(context)!.today,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 2),
            bar,
          ],
        );
      },
    );
  }
}

/// Ratings of this coffee by effective day after roasting, over the phase
/// bands of the style brewed most, with today and the sweet spot marked.
class _RatingByAgeChart extends StatelessWidget {
  const _RatingByAgeChart({required this.freshness});

  final CoffeeFreshness freshness;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final points = freshness.ratedDays;
    final espresso = points
        .where((point) => point.style == BrewStyle.espresso)
        .length;
    final style = espresso * 2 > points.length
        ? BrewStyle.espresso
        : BrewStyle.filter;
    final number = NumberFormat('0.#', regionalLocale.toString());
    // The best rating, the earliest day on ties.
    final best = points.reduce(
      (a, b) => b.rating > a.rating || (b.rating == a.rating && b.day < a.day)
          ? b
          : a,
    );
    final days = points.map((point) => point.day).toList()..sort();
    final summary = s.ratingByAgeSummary(
      points.length,
      days.first,
      days.last,
      number.format(best.rating),
      best.day,
    );
    return Semantics(
      label: '${s.ratingByAgeTitle}. $summary',
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('rating-by-age'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.ratingByAgeTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _RatingByAgePainter(
                points: points,
                window: freshness.windows[style]!,
                sweetSpot: freshness.sweetSpots[style],
                today: freshness.day,
                colors: theme.colorScheme,
                phaseColor: (phase) => freshnessPhaseColor(context, phase),
                labelStyle: theme.textTheme.labelSmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                todayLabel: s.today,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              '● ${brewStyleLabel(s, BrewStyle.filter)}',
              '■ ${brewStyleLabel(s, BrewStyle.espresso)}',
              s.chartPhasesFor(brewStyleLabel(s, style)),
            ].join('   '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingByAgePainter extends CustomPainter {
  _RatingByAgePainter({
    required this.points,
    required this.window,
    required this.sweetSpot,
    required this.today,
    required this.colors,
    required this.phaseColor,
    required this.labelStyle,
    required this.todayLabel,
  });

  final List<RatedDay> points;
  final FreshnessWindow window;
  final SweetSpot? sweetSpot;
  final int today;
  final ColorScheme colors;
  final Color Function(FreshnessPhase) phaseColor;
  final TextStyle labelStyle;
  final String todayLabel;

  static const _left = 22.0;
  static const _bottom = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final lastDay = [
      window.goodUntil,
      today + 2,
      ...points.map((point) => point.day + 2),
    ].reduce((a, b) => a > b ? a : b);
    final plot = Rect.fromLTRB(_left, 4, size.width - 4, size.height - _bottom);
    double x(num day) => plot.left + plot.width * day / lastDay;
    double y(num rating) => plot.bottom - plot.height * rating / 10;

    // Phase bands along the bottom edge and a light tint above them.
    final bands = [
      (0, window.primeStart, FreshnessPhase.degassing),
      (window.primeStart, window.primeEnd + 1, FreshnessPhase.prime),
      (window.primeEnd + 1, window.goodUntil + 1, FreshnessPhase.good),
      (window.goodUntil + 1, window.agingUntil + 1, FreshnessPhase.aging),
      (window.agingUntil + 1, lastDay, FreshnessPhase.stale),
    ];
    for (final (start, end, phase) in bands) {
      if (start >= lastDay) continue;
      final band = Rect.fromLTRB(
        x(start),
        plot.top,
        x(end.clamp(start, lastDay)),
        plot.bottom,
      );
      canvas.drawRect(
        band,
        Paint()..color = phaseColor(phase).withValues(alpha: 0.08),
      );
      canvas.drawRect(
        Rect.fromLTRB(band.left, plot.bottom - 4, band.right, plot.bottom),
        Paint()..color = phaseColor(phase).withValues(alpha: 0.6),
      );
    }

    if (sweetSpot case final spot?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x(spot.startDay),
            plot.top,
            x(spot.endDay + 1),
            plot.bottom - 4,
          ),
          const Radius.circular(4),
        ),
        Paint()
          ..color = colors.primary.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (final rating in [0, 5, 10]) {
      canvas.drawLine(
        Offset(plot.left, y(rating)),
        Offset(plot.right, y(rating)),
        grid,
      );
      _text(canvas, '$rating', Offset(0, y(rating) - 6));
    }
    _text(canvas, '0', Offset(plot.left - 3, plot.bottom + 3));
    _text(canvas, '$lastDay', Offset(plot.right - 14, plot.bottom + 3));

    final todayX = x(today.clamp(0, lastDay));
    final todayPaint = Paint()
      ..color = colors.onSurfaceVariant
      ..strokeWidth = 1.2;
    for (var dy = plot.top; dy < plot.bottom; dy += 6) {
      canvas.drawLine(Offset(todayX, dy), Offset(todayX, dy + 3), todayPaint);
    }
    // The label goes on the side of the line with room for it.
    final todayText = TextPainter(
      text: TextSpan(text: todayLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    todayText.paint(
      canvas,
      Offset(
        todayX + 3 + todayText.width > size.width
            ? todayX - 3 - todayText.width
            : todayX + 3,
        plot.top,
      ),
    );

    final fill = Paint()..color = colors.primary;
    final outline = Paint()
      ..color = colors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final point in points) {
      final center = Offset(x(point.day + 0.5), y(point.rating));
      if (point.style == BrewStyle.espresso) {
        final square = Rect.fromCenter(center: center, width: 9, height: 9);
        canvas.drawRect(square, fill);
        canvas.drawRect(square, outline);
      } else {
        canvas.drawCircle(center, 5, fill);
        canvas.drawCircle(center, 5, outline);
      }
    }
  }

  void _text(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_RatingByAgePainter old) =>
      old.points != points ||
      old.window != window ||
      old.today != today ||
      old.colors != colors ||
      old.sweetSpot != sweetSpot;
}
