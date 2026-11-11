import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_menu.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/frozen_stock_badge.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/semantic_colors.dart';
import 'package:holybeans/ui/core/settle_in.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:intl/intl.dart';

/// A coffee in the Beans list. Informative cards show the bag photo,
/// origin with flags, stock, freezer, roast, freshness phase, brews and
/// flavour notes; [compact] cards fit it in a list tile.
class BeanCard extends StatelessWidget {
  const BeanCard({
    super.key,
    required this.coffee,
    required this.data,
    required this.actions,
    this.compact = true,
  });

  final Coffee coffee;
  final JournalData data;
  final JournalActions actions;
  final bool compact;

  // A new coffee settles like a bag on the scale: its stock runs up to
  // what it weighs.
  @override
  Widget build(BuildContext context) => SettleIn(
    id: coffee.id,
    createdAtMs: coffee.createdAtMs,
    builder: (context, reveal, fill) {
      final facts = _BeanFacts(coffee, data, actions.read.portions);
      return SettleIn.open(
        reveal,
        compact
            // A compact card's stock sits inside a sentence, which a
            // running figure would shake; it only opens.
            ? _CompactBeanCard(facts: facts, data: data, actions: actions)
            : _InformativeBeanCard(
                facts: facts,
                data: data,
                actions: actions,
                fill: fill,
              ),
      );
    },
  );
}

/// What the cards say about a coffee: its origins, active bags, freezer
/// and brews.
class _BeanFacts {
  _BeanFacts(this.coffee, JournalData data, List<FrozenPortion> portions)
    : components = data.componentsOf(coffee.id),
      stock = CoffeeStock(
        lots: data.activeLotsOf(coffee.id),
        portions: portions,
        adjustments: data.adjustments,
      ),
      brewCount = data.brewCount(coffee.id);

  final Coffee coffee;
  final List<CoffeeComponent> components;
  final CoffeeStock stock;
  final int brewCount;

  String get flags => components
      .map((component) => coffeeCountryFor(component.country)?.flag)
      .whereType<String>()
      .toSet()
      .join(' ');

  /// Country and region of each origin, separated by " / ".
  String get origin => components
      .map(
        (component) => [component.country, component.region]
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .join(', '),
      )
      .where((text) => text.isNotEmpty)
      .join(' / ');

  /// The latest roast date among the active bags.
  DateTime? get roastDate => stock.lots
      .map((lot) => DateTime.tryParse(lot.roastDate ?? ''))
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (latest, date) =>
            latest == null || date.isAfter(latest) ? date : latest,
      );

  int? get roastAge => switch (roastDate) {
    final date? => daysSinceRoast(date, DateTime.now()),
    null => null,
  };

  /// Stock fill from 0 to 1, when both bought and left are known.
  double? get stockLevel {
    final initial = stock.initialGrams;
    final remaining = stock.signedRemainingGrams;
    if (initial == null || remaining == null || initial <= 0) return null;
    // All that is left is frozen: an empty bar would read as none left.
    if (remaining <= 0 && stock.frozen.isNotEmpty) return null;
    return (remaining / initial).clamp(0.0, 1.0);
  }
}

class _CompactBeanCard extends StatelessWidget {
  const _CompactBeanCard({
    required this.facts,
    required this.data,
    required this.actions,
  });

  final _BeanFacts facts;
  final JournalData data;
  final JournalActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final coffee = facts.coffee;
    final stock = facts.stock;
    final details = [
      [facts.flags, coffee.roaster].where((text) => text.isNotEmpty).join(' '),
      if (stock.remainingGrams case final grams?)
        formatGrams(grams, regionalLocale.toString()),
      if (stock.frozen.isNotEmpty)
        '${s.frozen} ${formatGrams(stock.frozenGrams, regionalLocale.toString())}',
      if (facts.roastAge case final age?) s.roastedDaysAgo(age),
      // In the Archived tab, when it was finished tells coffees apart.
      if (coffee.archivedAtMs case final ms?)
        s.archivedOn(
          DateFormat.yMMM(regionalLocale.toString())
              .format(DateTime.fromMillisecondsSinceEpoch(ms)),
        ),
    ].where((text) => text.trim().isNotEmpty).join(', ');
    return Card(
      key: ValueKey('bean-card-${coffee.id}'),
      // Holding it edits the bean, like Edit in its menu.
      child: Semantics(
        onLongPressHint: AppLocalizations.of(context)!.editBean,
        child: ListTile(
          title: Row(
            children: [
              if (coffee.isFavorite) const _FavoriteIcon(),
              FrozenStockBadge(
                state: frozenStockState(
                  stock.remainingGrams,
                  stock.frozenGrams,
                ),
              ),
              Flexible(
                child: Text(
                  coffee.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: details.isEmpty
              ? null
              : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (coffee.rating case final rating?) _CoffeeRating(rating),
              BeanMenu(
                coffee: coffee,
                hasBrews: facts.brewCount > 0,
                actions: actions,
              ),
            ],
          ),
          onTap: () => actions.navigation.showCoffeeDetails(coffee, data),
          onLongPress: () => actions.navigation.addCoffee(coffee),
        ),
      ),
    );
  }
}

class _InformativeBeanCard extends StatelessWidget {
  const _InformativeBeanCard({
    required this.facts,
    required this.data,
    required this.actions,
    required this.fill,
  });

  final _BeanFacts facts;
  final JournalData data;
  final JournalActions actions;

  /// How far the stock has run up while the card settles.
  final double fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final coffee = facts.coffee;
    final origin = facts.origin;
    final flags = facts.flags;
    final farmDetails = originDetails(
      facts.components,
      AppLocalizations.of(context)!.localeName,
    );
    final stockLevel = switch (facts.stockLevel) {
      final level? => level * fill,
      null => null,
    };
    final flavor = coffee.flavorProfile;
    return Card(
      key: ValueKey('bean-card-${coffee.id}'),
      // Holding it edits the bean, like Edit in its menu.
      child: Semantics(
        onLongPressHint: AppLocalizations.of(context)!.editBean,
        child: InkWell(
          customBorder: theme.cardTheme.shape,
          onTap: () => actions.navigation.showCoffeeDetails(coffee, data),
          onLongPress: () => actions.navigation.addCoffee(coffee),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Heading(facts: facts, data: data, actions: actions),
                if (coffee.roaster.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    coffee.roaster,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (origin.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text.rich(
                    key: ValueKey('bean-origin-${coffee.id}'),
                    TextSpan(
                      children: [
                        if (flags.isNotEmpty)
                          TextSpan(text: '$flags  ', semanticsLabel: ''),
                        TextSpan(text: origin),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (farmDetails.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    farmDetails,
                    key: ValueKey('bean-farm-${coffee.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                _BeanFactChips(
                  facts: facts,
                  freshness: actions.read.freshnessToday(facts.coffee),
                  fill: fill,
                ),
                if (stockLevel != null) ...[
                  const SizedBox(height: 10),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        key: ValueKey('bean-stock-${coffee.id}'),
                        value: stockLevel,
                        minHeight: 3,
                        color: colors.onSurfaceVariant,
                        backgroundColor: colors.outlineVariant,
                      ),
                    ),
                  ),
                ],
                // The description stays in the details: two lines of prose
                // made every card one screen tall in a long list.
                if (flavor != null && flavor.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FlavorNotes(profile: flavor, maxNotes: 3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bag photo, favourite, name, rating and menu.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.facts,
    required this.data,
    required this.actions,
  });

  final _BeanFacts facts;
  final JournalData data;
  final JournalActions actions;

  @override
  Widget build(BuildContext context) {
    final coffee = facts.coffee;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((actions.read.photos, data.coverOf(coffee.id)) case (
          final store?,
          final photo?,
        ))
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                store.file(photo),
                key: ValueKey('bean-thumb-${coffee.id}'),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                cacheWidth: 156,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 52, height: 52),
              ),
            ),
          ),
        if (coffee.isFavorite)
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: _FavoriteIcon(),
          ),
        FrozenStockBadge(
          state: frozenStockState(
            facts.stock.remainingGrams,
            facts.stock.frozenGrams,
          ),
        ),
        Expanded(
          child: Text(
            coffee.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (coffee.rating case final rating?) ...[
          const SizedBox(width: 8),
          _CoffeeRating(rating),
        ],
        BeanMenu(
          coffee: coffee,
          hasBrews: facts.brewCount > 0,
          actions: actions,
        ),
      ],
    );
  }
}

/// Stock, freezer, roast, decaf, freshness, brews and archive as chips.
class _BeanFactChips extends StatelessWidget {
  const _BeanFactChips({
    required this.facts,
    required this.freshness,
    required this.fill,
  });

  final _BeanFacts facts;
  final FreshnessToday? freshness;

  /// How far the stock has run up while the card settles.
  final double fill;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final coffee = facts.coffee;
    final stock = facts.stock;
    final remaining = stock.remainingGrams;
    final initial = stock.initialGrams;
    final frozenSummary = stock.frozen.isEmpty
        ? null
        : s.frozenSummary(
            formatGrams(stock.frozenGrams, regionalLocale.toString()),
            stock.frozen.length,
          );
    final frozenOnlyAge = stock.frozenOnlyAge;
    final roastDate = facts.roastDate;
    final roastAge = facts.roastAge;
    // How long the oldest portion has waited, next to how old it went in.
    final frozenDays =
        [
          for (final portion in stock.frozen)
            if (DateTime.tryParse(portion.frozenDate) case final date?)
              DateUtils.dateOnly(DateTime.now())
                  .difference(DateUtils.dateOnly(date))
                  .inDays,
        ].fold<int?>(
          null,
          (most, days) => most == null || days > most ? days : most,
        );
    final roastSummary = [
      if (coffee.roastLevel case final level?) roastLevelLabel(s, level),
      if (frozenOnlyAge != null) ...[
        s.frozenAtAge(frozenOnlyAge),
        if (frozenDays case final days?)
          days == 0
              ? s.homeFrozenToday
              : s.inFreezerFor(dayOrWeekSpan(s, days)),
      ] else if (roastAge != null)
        s.roastedDaysAgo(roastAge)
      else if (roastDate != null)
        formatRegionalDate(roastDate, regionalLocale),
    ].join(', ');
    final brewCount = facts.brewCount;
    final consumed = switch (stock.consumedGrams) {
      final grams? when grams > 0 => formatGrams(
        grams,
        regionalLocale.toString(),
      ),
      _ => null,
    };
    String stockText(double grams) => initial == null
        ? formatGrams(grams, regionalLocale.toString())
        : '${NumberFormat('0.#', regionalLocale.toString()).format(grams)} / ${formatGrams(initial, regionalLocale.toString())}';
    final chips = [
      if (remaining != null)
        CardFact(
          Icons.inventory_2_outlined,
          stockText(settledShare(remaining, fill)),
          settled: stockText(remaining),
          semanticLabel:
              '${s.remaining}: ${formatGrams(remaining, regionalLocale.toString())}',
          emphasized: true,
        ),
      if (frozenSummary != null)
        CardFact(
          Icons.ac_unit_rounded,
          frozenSummary,
          semanticLabel: '${s.frozen}: $frozenSummary',
          color: frozenColor(context),
        ),
      if (roastSummary.isNotEmpty)
        CardFact(Icons.local_fire_department_outlined, roastSummary),
      if (coffee.isDecaf) CardFact(Icons.bedtime_outlined, s.decaf),
      // The phase shown follows the style last brewed with this coffee;
      // frozen-only coffee is not ageing.
      if (freshness case final today?)
        _FreshnessChip(
          key: ValueKey('bean-freshness-${coffee.id}'),
          phase: today.phase,
          style: today.style,
        ),
      if (brewCount > 0)
        CardFact(
          Icons.coffee_outlined,
          [s.brewsCount(brewCount), ?consumed].join(', '),
          semanticLabel: [
            s.brewsCount(brewCount),
            if (consumed != null) '${s.consumed}: $consumed',
          ].join(', '),
        ),
      if (coffee.archivedAtMs case final ms?)
        CardFact(
          Icons.archive_outlined,
          s.archivedOn(
            DateFormat.yMMM(regionalLocale.toString())
                .format(DateTime.fromMillisecondsSinceEpoch(ms)),
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 16, runSpacing: 6, children: chips),
    );
  }
}

/// The freshness phase for the style last brewed, in its colour.
class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({super.key, required this.phase, required this.style});

  final FreshnessPhase phase;
  final BrewStyle style;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final color = freshnessPhaseColor(context, phase);
    final label = freshnessPhaseLabel(s, phase);
    final styleName = brewStyleLabel(s, style);
    final textStyle = Theme.of(context).textTheme.labelLarge;
    // The phase in its colour, then the style it was judged for.
    return Semantics(
      label: '${s.freshness}: $label, $styleName',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse_rounded, size: 17, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  $styleName',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteIcon extends StatelessWidget {
  const _FavoriteIcon();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Icon(
      Icons.favorite_rounded,
      size: 18,
      color: Theme.of(context).colorScheme.primary,
      semanticLabel: AppLocalizations.of(context)!.favorite,
    ),
  );
}

class _CoffeeRating extends StatelessWidget {
  const _CoffeeRating(this.rating);

  final double rating;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return RatingBadge(
      rating: rating,
      localeName: regionalLocale.toString(),
      semanticLabel:
          '${s.rating}: ${NumberFormat('0.#', regionalLocale.toString()).format(rating)} / 10',
    );
  }
}

/// Variety, process, altitude and producer of each origin, separated by
/// " / " in the same order as the origin line.
String originDetails(List<CoffeeComponent> components, String locale) {
  return components
      .map(
        (component) => [
          component.variety,
          component.process,
          altitudeLabel(component.altitudeMeters, component.altitudeMaxMeters),
          component.producer,
        ].whereType<String>().where((text) => text.isNotEmpty).join(', '),
      )
      .where((text) => text.isNotEmpty)
      .join(' / ');
}

/// A small icon-and-text chip on a bean card.
class CardFact extends StatelessWidget {
  const CardFact(
    this.icon,
    this.text, {
    super.key,
    this.emphasized = false,
    this.color,
    this.semanticLabel,
    this.settled,
  });

  final IconData icon;
  final String text;

  /// The text once a settling card has finished; its width is kept while
  /// the figure runs up.
  final String? settled;
  final bool emphasized;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Plain icon and text: a figure when it is the stock, muted otherwise.
    final fact = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color ?? colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: SteadyText(
            text,
            settled: settled ?? text,
            style: emphasized
                ? AppTheme.figures(theme.textTheme.titleMedium)
                      .copyWith(color: colors.onSurface)
                : theme.textTheme.labelLarge?.copyWith(
                    color: color ?? colors.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
          ),
        ),
      ],
    );
    return semanticLabel == null
        ? fact
        : Semantics(label: semanticLabel, excludeSemantics: true, child: fact);
  }
}
