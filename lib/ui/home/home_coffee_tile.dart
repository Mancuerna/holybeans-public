import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

/// A coffee at hand on Home: what is left, where it stands in its freshness
/// window and the recipe Repeat starts from (its favourite, else its last
/// brew). Tapping the coffee opens its details; tapping the recipe opens
/// that brew.
class HomeCoffeeTile extends StatelessWidget {
  const HomeCoffeeTile({
    super.key,
    required this.coffee,
    required this.freshGrams,
    required this.freshness,
    required this.seed,
    required this.data,
    required this.actions,
    required this.journal,
    this.low = false,
  });

  final Coffee coffee;
  final double? freshGrams;
  final FreshnessToday? freshness;

  /// The brew Repeat and Adjust start from; null if never brewed.
  final Brew? seed;
  final JournalData data;
  final JournalNavigation actions;
  final JournalRead journal;

  /// Fewer than two doses left: the grams take the warning colour.
  final bool low;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final dose = seed?.doseGrams;
    final grams = freshGrams;
    return Card(
      key: ValueKey('home-coffee-${coffee.id}'),
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => actions.showCoffeeDetails(coffee, data),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        coffee.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (grams != null) ...[
                      const SizedBox(width: 12),
                      // At the edge, and never more than a third of the
                      // screen, so the name keeps room with large text.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width / 3,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                formatGrams(grams, regionalLocale.toString()),
                                style: AppTheme.figures(
                                  theme.textTheme.titleLarge,
                                ).copyWith(color: low ? colors.primary : null),
                              ),
                            ),
                            if (dose != null && dose > 0)
                              Text(
                                s.dosesLeft((grams / dose + 1e-9).floor()),
                                textAlign: TextAlign.end,
                                style: muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (freshness case final freshness?) ...[
                const SizedBox(height: 10),
                _Freshness(freshness: freshness),
              ],
              const SizedBox(height: 6),
              Divider(height: 12, color: colors.outlineVariant),
              if (seed case final brew?)
                _Recipe(
                  brew: brew,
                  coffee: coffee,
                  data: data,
                  actions: actions,
                  journal: journal,
                )
              else
                Row(
                  children: [
                    Expanded(child: Text(s.homeNotBrewedYet, style: muted)),
                    FilledButton.tonalIcon(
                      key: ValueKey('home-brew-${coffee.id}'),
                      onPressed: () => actions.openBrewForm(
                        data.coffees,
                        initialCoffeeId: coffee.id,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(s.homeFirstBrew),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phase, how long it lasts and the window with today marked.
class _Freshness extends StatelessWidget {
  const _Freshness({required this.freshness});

  final FreshnessToday freshness;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final timing = freshnessTimeLabel(s, freshness.window, freshness.day);
    final label = [freshnessPhaseLabel(s, freshness.phase), ?timing].join(', ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FreshnessPhaseChip(phase: freshness.phase),
                if (timing != null)
                  Text(
                    timing,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            FreshnessBar(day: freshness.day, window: freshness.window),
          ],
        ),
      ),
    );
  }
}

/// The recipe to repeat, as figures, with Adjust and Repeat beside it.
class _Recipe extends StatelessWidget {
  const _Recipe({
    required this.brew,
    required this.coffee,
    required this.data,
    required this.actions,
    required this.journal,
  });

  final Brew brew;
  final Coffee coffee;
  final JournalData data;
  final JournalNavigation actions;
  final JournalRead journal;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parts = brewRecipeParts(
      brew,
      journal.methods,
      regionalLocale.toString(),
      hidden: journal.hiddenParameters,
    );
    final when = relativeTimeInline(
      s,
      DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs),
      DateTime.now(),
    );
    final rating = brew.rating;
    final caption = Text.rich(
      TextSpan(
        children: [
          if (brew.isFavorite)
            TextSpan(
              text: '${s.favoriteRecipe} · ',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          TextSpan(text: s.homeRecipeWhen(brew.methodName, when)),
          if (rating != null) ...[
            const TextSpan(text: ' · '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: colors.onSurfaceVariant,
                semanticLabel: s.rating,
              ),
            ),
            TextSpan(
              text: formatDecimal(
                rating,
                pattern: '0.#',
                locale: regionalLocale.toString(),
              ),
            ),
          ],
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );
    final buttons = [
      IconButton(
        key: ValueKey('home-adjust-${coffee.id}'),
        tooltip: s.adjustBrew,
        onPressed: () => actions.openBrewForm(
          data.coffees,
          seed: brew,
          repeat: true,
          adjust: true,
        ),
        icon: const Icon(Icons.tune_rounded),
      ),
      FilledButton.tonalIcon(
        key: ValueKey('home-repeat-${coffee.id}'),
        onPressed: () =>
            actions.openBrewForm(data.coffees, seed: brew, repeat: true),
        icon: const Icon(Icons.replay_rounded),
        label: Text(s.repeatBrew),
      ),
    ];
    // The figures take the whole width so they stay on one line; the
    // buttons share the caption's line while it keeps room to read, and go
    // below it on narrow screens or with large text.
    final wide =
        MediaQuery.sizeOf(context).width >=
        MediaQuery.textScalerOf(context).scale(360);
    return InkWell(
      key: ValueKey('home-recipe-${coffee.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => actions.showBrewDetails(brew, coffee, data),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BrewRecipeFigures(parts),
            ),
          if (wide)
            Row(
              children: [
                Expanded(child: caption),
                ...buttons,
              ],
            )
          else ...[
            caption,
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: buttons,
            ),
          ],
        ],
      ),
    );
  }
}
