import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_delete.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/settle_in.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:intl/intl.dart';

/// The recipe in parts such as "18 g → 288 g", "1:16" and "3:00", without
/// the [hidden] parameters. With [fill] below 1 the output and the time
/// are that share of their value, as they run up when a brew settles.
List<String> brewRecipeParts(
  Brew brew,
  List<BrewMethod> methods,
  String localeName, {
  Set<BrewParameter> hidden = const {},
  double fill = 1,
}) {
  final method = methods.where((row) => row.id == brew.methodId).firstOrNull;
  final water = hidden.contains(BrewParameter.water) ? null : brew.waterGrams;
  final beverage = hidden.contains(BrewParameter.beverage)
      ? null
      : brew.beverageGrams;
  final output = switch (water ?? beverage) {
    final grams? => settledShare(grams, fill),
    null => null,
  };
  final ratio = hidden.contains(BrewParameter.ratio)
      ? null
      : formatBrewRatio(
          methodCategory: method?.category,
          methodName: method?.name ?? brew.methodName,
          doseGrams: brew.doseGrams,
          waterGrams: brew.waterGrams,
          beverageGrams: brew.beverageGrams,
          localeName: localeName,
        );
  final parts = [
    if (brew.doseGrams != null && output != null)
      '${formatGrams(brew.doseGrams!, localeName)} → ${formatGrams(output, localeName)}'
    else if (brew.doseGrams != null)
      formatGrams(brew.doseGrams!, localeName)
    else if (output != null)
      formatGrams(output, localeName),
    ?ratio,
    if (brew.timeSeconds case final seconds?)
      formatDuration((seconds * fill).round()),
  ];
  return parts;
}

/// [brewRecipeParts] as one line of text, e.g. "18 g → 288 g, 1:16, 3:00".
String? brewRecipeLine(
  Brew brew,
  List<BrewMethod> methods,
  String localeName, {
  Set<BrewParameter> hidden = const {},
}) {
  final parts = brewRecipeParts(brew, methods, localeName, hidden: hidden);
  return parts.isEmpty ? null : parts.join(', ');
}

/// The recipe as figures side by side: dose and output, ratio and time.
class BrewRecipeFigures extends StatelessWidget {
  const BrewRecipeFigures(
    this.parts, {
    super.key,
    this.large = false,
    this.semanticLabel,
    this.settled,
  });

  final List<String> parts;

  /// The parts once a settling card has finished, whose widths are kept so
  /// the figures do not shift while they run up.
  final List<String>? settled;

  /// What screen readers hear; the parts by default.
  final String? semanticLabel;

  /// Bigger figures, for full cards.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTheme.figures(
      large ? theme.textTheme.titleLarge : theme.textTheme.titleMedium,
    );
    return Semantics(
      label: semanticLabel ?? parts.join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: large ? 20 : 16,
        runSpacing: 2,
        children: [
          for (final (index, part) in parts.indexed)
            SteadyText(
              part,
              settled: settled?.elementAtOrNull(index) ?? part,
              style: style,
            ),
        ],
      ),
    );
  }
}

/// A brew in a list: coffee identity, method, time, recipe and grinder.
/// Opens its details; the menu repeats,
/// rates, edits, shares or archives it.
class BrewCard extends StatelessWidget {
  const BrewCard({
    super.key,
    required this.brew,
    required this.data,
    required this.actions,
    this.showDate = true,
  });

  final Brew brew;
  final JournalData data;
  final JournalActions actions;

  /// Shows the date with the time; lists grouped by day show only the time.
  final bool showDate;

  @override
  Widget build(BuildContext context) => SettleIn(
    id: brew.id,
    createdAtMs: brew.createdAtMs,
    builder: (context, reveal, fill) =>
        SettleIn.open(reveal, _card(context, fill)),
  );

  Widget _card(BuildContext context, double fill) {
    final s = AppLocalizations.of(context)!;
    final coffee = data.coffees
        .where((row) => row.id == brew.coffeeId)
        .firstOrNull;
    final deviceLocale = regionalLocale;
    final brewTimestamp = showDate
        ? formatBrewTimestamp(brew, deviceLocale)
        : regionalTimeFormat(deviceLocale.toString())
              .format(DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs));
    final hidden = actions.hiddenParameters;
    bool shows(BrewParameter parameter) => !hidden.contains(parameter);
    final recipe = brewRecipeParts(
      brew,
      actions.methods,
      regionalLocale.toString(),
      hidden: hidden,
      fill: fill,
    );
    final finalRecipe = fill >= 1
        ? recipe
        : brewRecipeParts(
            brew,
            actions.methods,
            regionalLocale.toString(),
            hidden: hidden,
          );
    final processes = data
        .componentsOf(brew.coffeeId)
        .map((component) => component.process?.trim() ?? '')
        .where((process) => process.isNotEmpty)
        .toSet()
        .join(' / ');
    final identity = [
      if (processes.isNotEmpty) processes,
      if (coffee != null && coffee.roaster.trim().isNotEmpty)
        coffee.roaster.trim(),
    ].join(' · ');
    final equipment = _equipmentLine(s, shows);
    final rating = brew.rating == null || !shows(BrewParameter.rating)
        ? null
        : RatingBadge(
            rating: brew.rating!,
            localeName: regionalLocale.toString(),
            semanticLabel:
                '${s.rating}: ${NumberFormat('0.#', regionalLocale.toString()).format(brew.rating)} / 10',
          );
    final subtitle = [
      brew.methodName,
      brewTimestamp,
      if (brew.archivedAtMs != null) s.archivedStatus,
      if (brew.stockReviewPending == true) s.stockReviewTitle,
    ].join(' · ');
    final theme = Theme.of(context);
    // The favourite recipe of its coffee and method.
    final favoriteStar = brew.isFavorite
        ? WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.favorite_rounded,
                key: ValueKey('brew-favorite-${brew.id}'),
                size: 18,
                color: theme.colorScheme.primary,
                semanticLabel: s.favoriteRecipe,
              ),
            ),
          )
        : null;
    // A shortcut to Edit, which the menu also has; screen readers hear it.
    void onLongPress() => _onAction(context, 'edit', coffee);
    return Card(
      key: ValueKey('brew-card-${brew.id}'),
      child: Semantics(
        onLongPressHint: s.editBrew,
        child: InkWell(
          customBorder: theme.cardTheme.shape,
          onTap: () => actions.showBrewDetails(brew, coffee, data),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              ?favoriteStar,
                              TextSpan(text: coffee?.name ?? '—'),
                            ],
                          ),
                          // Two lines at most, also with large text.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (rating != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 8),
                        child: rating,
                      ),
                    _actionsMenu(context, coffee),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _BrewCardLines(
                    brewId: brew.id,
                    recipe: recipe,
                    settledRecipe: finalRecipe,
                    identity: identity,
                    subtitle: subtitle,
                    equipment: equipment,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Grinder and setting, respecting hidden parameters.
  String _equipmentLine(
    AppLocalizations s,
    bool Function(BrewParameter parameter) shows,
  ) {
    final grinderName = shows(BrewParameter.grinder)
        ? brew.grinderName?.trim()
        : null;
    final grindSetting = shows(BrewParameter.grindSetting)
        ? brew.grindSetting?.trim()
        : null;
    return [
      if (brew.isPreGround && shows(BrewParameter.grinder))
        s.preGround
      else if (!brew.isPreGround) ...[
        if (grinderName != null && grinderName.isNotEmpty) grinderName,
        if (grindSetting != null && grindSetting.isNotEmpty) grindSetting,
      ],
    ].join(' · ');
  }

  Widget _actionsMenu(BuildContext context, Coffee? coffee) {
    final s = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: s.actions,
      onSelected: (value) => _onAction(context, value, coffee),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'repeat', child: Text(s.repeatBrew)),
        PopupMenuItem(value: 'rate', child: Text(s.rateBrew)),
        PopupMenuItem(value: 'edit', child: Text(s.editBrew)),
        PopupMenuItem(value: 'share', child: Text(s.shareText)),
        PopupMenuItem(
          key: ValueKey('brew-compare-${brew.id}'),
          value: 'compare',
          child: Text(s.compareBrews),
        ),
        if (brew.methodId != null)
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              brew.isFavorite ? s.unmarkFavoriteRecipe : s.markFavoriteRecipe,
            ),
          ),
        if (brew.archivedByCoffee != true)
          PopupMenuItem(
            value: 'archive',
            child: Text(
              brew.archivedAtMs == null ? s.archiveBrew : s.unarchiveBrew,
            ),
          ),
        if (canDeleteBrew(brew, coffee))
          PopupMenuItem(
            key: ValueKey('brew-delete-${brew.id}'),
            value: 'delete',
            child: Text(s.deleteBrew),
          ),
      ],
    );
  }

  void _onAction(BuildContext context, String value, Coffee? coffee) {
    switch (value) {
      case 'repeat':
        actions.openBrewForm(data.coffees, seed: brew, repeat: true);
      case 'rate':
        actions.rateBrew(brew, coffee);
      case 'favorite':
        actions.setBrewFavorite(brew, favorite: !brew.isFavorite);
      case 'edit':
        actions.openBrewForm(data.coffees, existing: brew);
      case 'share':
        if (coffee != null) {
          actions.shareBrew(brew, coffee, data.componentsOf(coffee.id));
        }
      case 'compare':
        actions.compareBrew(brew, data);
      case 'archive':
        actions.archiveBrew(brew);
      case 'delete':
        deleteBrewAfterConfirming(context, actions, brew);
    }
  }
}

/// Coffee identity, method and time, recipe and grinder below the title.
class _BrewCardLines extends StatelessWidget {
  const _BrewCardLines({
    required this.brewId,
    required this.recipe,
    required this.settledRecipe,
    required this.subtitle,
    required this.equipment,
    required this.identity,
  });

  final String brewId;
  final List<String> recipe;

  /// The finished recipe: its width is kept and screen readers hear it
  /// while the figures run up.
  final List<String> settledRecipe;
  final String subtitle;
  final String equipment;
  final String identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (identity.isNotEmpty)
          Text(identity, style: theme.textTheme.bodyMedium),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: muted),
        ),
        if (recipe.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: BrewRecipeFigures(
              recipe,
              key: ValueKey('brew-recipe-$brewId'),
              semanticLabel: settledRecipe.join(', '),
              settled: settledRecipe,
            ),
          ),
        if (equipment.isNotEmpty)
          Text(
            equipment,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
