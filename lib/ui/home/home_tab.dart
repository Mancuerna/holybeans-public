import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/coffee_year.dart';
import 'package:holybeans/domain/home_coffees.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/backup/backup_cards.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/page_layout.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/home/home_coffee_tile.dart';
import 'package:holybeans/ui/home/home_stock_data.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/year_review/year_review_data.dart';
import 'package:holybeans/ui/year_review/year_review_entry.dart';

/// Home: stock and the week at a glance, backups, beans running low and the
/// coffees at hand by freshness, each with the recipe to repeat.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.data,
    required this.actions,
    this.now,
  });

  final DateTime? now;
  final JournalData data;
  final JournalActions actions;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  JournalData get data => widget.data;
  JournalActions get actions => widget.actions;
  DateTime? get now => widget.now;
  (JournalData, List<FrozenPortion>)? _stockKey;
  late HomeStockData _stock;

  @override
  Widget build(BuildContext context) {
    final coffees = data.coffees;
    final brews = data.brews;
    final lots = data.lots;
    final s = AppLocalizations.of(context)!;
    final key = (data, actions.portions);
    if (key != _stockKey) {
      _stock = homeStockData(data, key.$2);
      _stockKey = key;
    }
    final active = _stock.active;
    final activeBrews = _stock.activeBrews;
    final atHand = _stock.atHand;
    final lastBrewAt = _stock.lastBrewAt;
    final freshByCoffee = _stock.freshByCoffee;
    final oldestFreeze = oldestFreezeDays(
      lots,
      actions.portions,
      DateTime.now(),
    );
    return JournalPage(
      children: [
        if (seasonalCoffeeYear([
              ...?data.overview?.yearDates,
              ...yearJournalDates(brews, lots),
            ], now ?? DateTime.now())
            case final year?) ...[
          YearReviewEntry(
            loadBrews: data.reads?.analytics,
            lots: lots,
            brews: brews,
            coffees: coffees,
            components: data.components,
            methods: actions.methods,
            year: year,
            now: now,
            photos: actions.photos,
            photoOf: (brew) async =>
                (await actions.repository.brewPhotos(brew.id)).firstOrNull ??
                (await actions.repository.coffeePhotos(brew.coffeeId))
                    .firstOrNull,
          ),
          const SizedBox(height: 18),
        ],
        if (coffees.isNotEmpty) ...[
          StatGrid(
            key: const ValueKey('home-summary'),
            items: [
              StatItem(
                s.availableFresh,
                formatGrams(_stock.freshTotal, regionalLocale.toString()),
              ),
              StatItem(
                s.frozen,
                formatGrams(_stock.frozenTotal, regionalLocale.toString()),
                caption: switch (oldestFreeze) {
                  null => null,
                  0 => s.homeFrozenToday,
                  final days => s.homeOldestFreeze(dayOrWeekSpan(s, days)),
                },
                frozen: true,
              ),
              // When the last brew was is on the cards below; the week's
              // count is not.
              if (brews.isNotEmpty)
                StatItem(
                  s.homeWeekTile,
                  s.brewsCount(
                    data.overview?.weekCountAt(now ?? DateTime.now()) ??
                        brews
                            .where(
                              (brew) =>
                                  brew.brewedAtMs >=
                                  (now ?? DateTime.now())
                                      .subtract(const Duration(days: 7))
                                      .millisecondsSinceEpoch,
                            )
                            .length,
                  ),
                  key: const ValueKey('home-week-brews'),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        BackupReminders(
          center: actions.backupCenter,
          firstBrewCreatedMs: data.overview?.firstCreatedMs,
          coffees: coffees,
          brews: brews,
          onExport: actions.exportBackup,
          onSaveToFolder: actions.saveBackupToFolder,
          onChooseFolder: actions.chooseBackupFolder,
        ),
        if (_stock.low case final low when low.isNotEmpty) ...[
          _LowStockCard(low: low, data: data, actions: actions),
          const SizedBox(height: 22),
        ],
        if (atHand.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: SectionTitle(s.homeYourCoffees)),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextButton(
                  key: const ValueKey('home-see-all-beans'),
                  onPressed: actions.showAllBeans,
                  child: Text(s.seeAll),
                ),
              ),
            ],
          ),
          _YourCoffees(
            coffees: atHand,
            brewsByCoffee: _stock.brewsByCoffee,
            lastBrewAt: lastBrewAt,
            freshGrams: freshByCoffee,
            low: _stock.lowIds,
            data: data,
            actions: actions,
          ),
        ],
        if (active.isEmpty && activeBrews.isEmpty) EmptyMessage(s.noBeans),
      ],
    );
  }
}

/// Coffees with fewer than two doses of unfrozen coffee left, with the
/// frozen coffee that could replace them; each opens its details.
class _LowStockCard extends StatelessWidget {
  const _LowStockCard({
    required this.low,
    required this.data,
    required this.actions,
  });

  final List<LowStock> low;
  final JournalData data;
  final JournalActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('home-low-stock'),
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.runningLow,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            for (final item in low)
              ListTile(
                key: ValueKey('low-stock-${item.coffee.id}'),
                contentPadding: const EdgeInsets.only(left: 28, right: 4),
                visualDensity: VisualDensity.compact,
                title: Text(
                  item.coffee.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    s.dosesLeft(item.doses),
                    if (item.frozenGrams > 0)
                      s.inFreezer(
                        formatGrams(
                          item.frozenGrams,
                          regionalLocale.toString(),
                        ),
                      ),
                  ].join(', '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                // What is left, as the figure to notice.
                trailing: Text(
                  formatGrams(item.freshGrams, regionalLocale.toString()),
                  style: AppTheme.figures(theme.textTheme.titleLarge)
                      .copyWith(color: colors.primary),
                ),
                onTap: () => actions.showCoffeeDetails(item.coffee, data),
              ),
          ],
        ),
      ),
    );
  }
}

/// The coffees at hand by freshness: a few to use soon and a few ready,
/// each with its recipe to repeat; while there is room, those resting that
/// were brewed and those without a roast date; and how many others rest.
class _YourCoffees extends StatelessWidget {
  const _YourCoffees({
    required this.coffees,
    required this.brewsByCoffee,
    required this.lastBrewAt,
    required this.freshGrams,
    required this.low,
    required this.data,
    required this.actions,
  });

  final List<Coffee> coffees;

  /// Active brews grouped by coffee, preserving their original order.
  final Map<String, List<Brew>> brewsByCoffee;
  final Map<String, int> lastBrewAt;
  final Map<String, double> freshGrams;

  /// Coffees running low.
  final Set<String> low;
  final JournalData data;
  final JournalActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final freshness = {
      for (final coffee in coffees) coffee.id: actions.freshnessToday(coffee),
    };
    final home = homeCoffees([
      for (final coffee in coffees)
        (
          id: coffee.id,
          phase: freshness[coffee.id]?.phase,
          daysLeft: switch (freshness[coffee.id]) {
            final today? => today.window.daysLeftInPhase(today.day),
            null => null,
          },
          lastBrewedAtMs: lastBrewAt[coffee.id],
          createdAtMs: coffee.createdAtMs,
        ),
    ]);
    final byId = {for (final coffee in coffees) coffee.id: coffee};
    Widget tile(String id) {
      final coffee = byId[id]!;
      return HomeCoffeeTile(
        coffee: coffee,
        freshGrams: freshGrams[id],
        freshness: freshness[id],
        seed: repeatSeed(
          brewsByCoffee[id] ?? const [],
          isFavorite: (brew) => brew.isFavorite,
          brewedAtMs: (brew) => brew.brewedAtMs,
        ),
        low: low.contains(id),
        data: data,
        actions: actions,
      );
    }

    List<Widget> group(String key, String title, int count, List<String> ids) =>
        [
          _GroupTitle(key: ValueKey('home-group-$key'), title, count: count),
          for (final id in ids) ...[tile(id), const SizedBox(height: 10)],
          const SizedBox(height: 8),
        ];

    return Column(
      key: const ValueKey('home-your-coffees'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (home.spendSoon.isNotEmpty)
          ...group(
            'spend-soon',
            s.homeSpendSoon,
            home.spendSoonCount,
            home.spendSoon,
          ),
        if (home.ready.isNotEmpty)
          ...group('ready', s.homeReady, home.readyCount, home.ready),
        if (home.resting.isNotEmpty)
          ...group('resting', s.homeResting, home.restingCount, home.resting),
        if (home.waitingCount > 0)
          _Summary(
            key: const ValueKey('home-resting'),
            icon: Icons.hourglass_top_rounded,
            title: home.resting.isEmpty ? s.homeResting : s.homeRestingOthers,
            text: home.firstReadyInDays == null
                ? null
                : s.homeRestingSummary(
                    home.waitingCount,
                    home.firstReadyInDays!,
                  ),
            onTap: actions.showAllBeans,
          ),
        if (home.undated.isNotEmpty)
          ...group('undated', s.homeUndated, home.undatedCount, home.undated)
        else if (home.undatedCount > 0)
          _Summary(
            key: const ValueKey('home-undated'),
            icon: Icons.event_busy_rounded,
            title: s.homeUndated,
            text: s.homeUndatedSummary(home.undatedCount),
            onTap: actions.showAllBeans,
          ),
      ],
    );
  }
}

/// A group's name, and how many coffees it has when not all are shown.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {super.key, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '$title · $count',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Coffees summed up in one line, which opens Beans.
class _Summary extends StatelessWidget {
  const _Summary({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: colors.onSurfaceVariant),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: text == null
            ? null
            : Text(
                text!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
