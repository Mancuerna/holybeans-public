import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/coffee_countries.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/coffee_details_header.dart';
import 'package:holybeans/ui/beans/freezer_widgets.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/beans/stock_adjustment_section.dart';
import 'package:holybeans/ui/brews/brew_card.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/page_layout.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the bottom sheet with everything about [coffee].
void showCoffeeDetailsSheet(
  BuildContext context,
  JournalActions actions,
  Coffee coffee,
  JournalData data,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) =>
      CoffeeDetailsSheet(actions: actions, coffee: coffee, data: data),
);

/// A coffee's stock, roast and price, freshness, freezer, origins, notes
/// and recent brews, with favourite, edit, archive and brew actions. Lots
/// and freezer portions stay live while it is open.
class CoffeeDetailsSheet extends StatefulWidget {
  const CoffeeDetailsSheet({
    super.key,
    required this.actions,
    required this.coffee,
    required this.data,
  });

  final JournalActions actions;
  final Coffee coffee;
  final JournalData data;

  @override
  State<CoffeeDetailsSheet> createState() => _CoffeeDetailsSheetState();
}

class _CoffeeDetailsSheetState extends State<CoffeeDetailsSheet> {
  // Opened once, so rebuilding the sheet does not resubscribe.
  late final Stream<List<String>> photos = widget.actions.repository
      .watchCoffeePhotos(widget.coffee.id);
  late final Stream<List<CoffeeLot>> lotStream = widget.actions.repository
      .watchLots();
  late final Stream<List<FrozenPortion>> portionStream = widget
      .actions
      .repository
      .watchFrozenPortions();

  late final adjustmentStream = widget.actions.repository
      .watchStockAdjustments();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StockAdjustment>>(
    stream: adjustmentStream,
    initialData: widget.data.adjustments,
    builder: (context, snapshot) => _build(context, snapshot.data ?? const []),
  );

  Widget _build(BuildContext context, List<StockAdjustment> adjustments) {
    final actions = widget.actions;
    final coffee = widget.coffee;
    final data = widget.data;
    return StreamBuilder<List<CoffeeLot>>(
      stream: lotStream,
      builder: (context, lotSnapshot) => StreamBuilder<List<FrozenPortion>>(
        stream: portionStream,
        initialData: actions.portions,
        builder: (context, portionSnapshot) {
          final lots = lotSnapshot.hasData
              ? [
                  for (final lot in lotSnapshot.data!)
                    if (lot.coffeeId == coffee.id && lot.archivedAtMs == null)
                      lot,
                ]
              : data.activeLotsOf(coffee.id);
          final stock = CoffeeStock(
            lots: lots,
            adjustments: adjustments,
            portions: portionSnapshot.data ?? const [],
          );
          final brews =
              data.brews.where((brew) => brew.coffeeId == coffee.id).toList()
                ..sort((a, b) => b.brewedAtMs.compareTo(a.brewedAtMs));
          final freshness = coffeeFreshness(
            coffee: coffee,
            lots: lots,
            coffees: data.coffees,
            brews: data.brews,
            allLots: lotSnapshot.data ?? lots,
            components: data.components,
            methods: actions.methods,
            frozenOnlyAge: stock.frozenOnlyAge,
          );
          final components = data.componentsOf(coffee.id);
          final notes = coffee.notes?.trim() ?? '';
          return DetailSheetContent(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoffeeDetailsHeader(actions: actions, coffee: coffee),
                if (actions.photos case final store?)
                  _Photos(stream: photos, store: store),
                _Extras(
                  actions: actions,
                  coffee: coffee,
                  data: data,
                  stock: stock,
                ),
                const SizedBox(height: 16),
                StatGrid(
                  items: _coffeeStats(
                    AppLocalizations.of(context)!,
                    coffee,
                    stock,
                    brewCount: brews.length,
                  ),
                ),
                StockAdjustmentSection(
                  repository: actions.repository,
                  coffee: coffee,
                  stock: stock,
                  adjustments: adjustments
                      .where((r) => r.coffeeId == coffee.id)
                      .toList(),
                ),
                if (freshness != null) ...[
                  const SizedBox(height: 20),
                  FreshnessSection(freshness: freshness),
                ],
                _FreezerSection(
                  actions: actions,
                  coffee: coffee,
                  data: data,
                  stock: stock,
                ),
                if (components.isNotEmpty) const SizedBox(height: 16),
                _OriginRows(components: components),
                if (notes.isNotEmpty)
                  DetailRow(
                    AppLocalizations.of(context)!.notes,
                    notes,
                    stacked: true,
                  ),
                _RecentBrews(
                  actions: actions,
                  coffee: coffee,
                  data: data,
                  brews: brews,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Stock, roast, rating and price tiles.
List<StatItem> _coffeeStats(
  AppLocalizations s,
  Coffee coffee,
  CoffeeStock stock, {
  required int brewCount,
}) {
  String grams(double value) => formatGrams(value, regionalLocale.toString());
  final initial = stock.initialGrams;
  final consumed = stock.consumedGrams;
  final pricePerKg = pricePerKgFor(
    paidPriceCents: coffee.paidPriceCents,
    initialGrams: initial,
  );
  final roastDates = [
    for (final lot in stock.lots) ?DateTime.tryParse(lot.roastDate ?? ''),
  ]..sort();
  final deviceLocale = regionalLocale;
  return [
    if (stock.lots.isNotEmpty)
      StatItem(s.remaining, switch (stock.remainingGrams) {
        final remaining? => grams(remaining),
        null => s.unknownStock,
      }, caption: initial == null ? null : '/ ${grams(initial)}'),
    if (stock.frozen.isNotEmpty)
      StatItem(s.frozen, grams(stock.frozenGrams), frozen: true),
    if (brewCount > 0)
      StatItem(
        s.consumed,
        consumed == null ? s.brewsCount(brewCount) : grams(consumed),
        caption: consumed == null ? null : s.brewsCount(brewCount),
      ),
    for (final roastDate in roastDates)
      StatItem(
        beanDetailLabel(s.roastDate),
        formatRegionalDate(roastDate, deviceLocale),
        caption: switch (daysSinceRoast(roastDate, DateTime.now())) {
          final days? => s.roastedDaysAgo(days),
          null => null,
        },
      ),
    if (coffee.roastLevel case final level?)
      StatItem(s.roastLevel, roastLevelLabel(s, level)),
    if (coffee.rating case final rating?)
      StatItem(
        s.rating,
        '${NumberFormat('0.#', regionalLocale.toString()).format(rating)} / 10',
      ),
    if (coffee.paidPriceCents case final cents?)
      StatItem(
        beanDetailLabel(s.paidPrice),
        formatEuro(cents / 100, regionalLocale.toString()),
      ),
    if (pricePerKg != null)
      StatItem(
        s.pricePerKg,
        '${formatEuro(pricePerKg, regionalLocale.toString())}/kg',
      ),
  ];
}

class _Photos extends StatelessWidget {
  const _Photos({required this.stream, required this.store});

  final Stream<List<String>> stream;
  final PhotoStore store;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<String>>(
    stream: stream,
    builder: (context, snapshot) => switch (snapshot.data ?? const []) {
      [] => const SizedBox.shrink(),
      final files => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: DetailPhotos(
          store: store,
          files: files,
          label: AppLocalizations.of(context)!.bagPhoto,
        ),
      ),
    },
  );
}

/// Flavour notes, decaf, the shop link and, for an active coffee, the
/// button to brew it.
class _Extras extends StatelessWidget {
  const _Extras({
    required this.actions,
    required this.coffee,
    required this.data,
    required this.stock,
  });

  final JournalActions actions;
  final Coffee coffee;
  final JournalData data;
  final CoffeeStock stock;

  /// Brews this coffee; when all of it is frozen, thaws a portion first,
  /// as the portion's own "Thaw and brew" does, so the dose comes out of
  /// the freezer and not out of an empty bag.
  Future<void> _brew(BuildContext context) async {
    if (!stock.onlyFrozen) {
      Navigator.pop(context);
      await actions.openBrewForm(data.coffees, initialCoffeeId: coffee.id);
      return;
    }
    final portions = stock.frozenOldestFirst;
    final portion = portions.length == 1
        ? portions.single
        : await _choosePortion(context, portions);
    if (portion == null || !context.mounted) return;
    await _thawThenBrew(
      context,
      actions,
      data,
      coffee,
      portion,
      note: AppLocalizations.of(context)!.onlyFrozenLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coffee.flavorProfile case final flavor?) ...[
          const SizedBox(height: 12),
          FlavorNotes(profile: flavor),
        ],
        if (coffee.isDecaf || coffee.shopUrl != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (coffee.isDecaf)
                Chip(
                  key: const ValueKey('coffee-decaf-chip'),
                  avatar: const Icon(Icons.bedtime_outlined, size: 18),
                  label: Text(s.decaf),
                ),
              if (coffee.shopUrl case final url?)
                TextButton.icon(
                  key: const ValueKey('coffee-shop-link'),
                  onPressed: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(s.openShop),
                ),
            ],
          ),
        ],
        if (coffee.archivedAtMs == null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('brew-with-bean-button'),
              onPressed: () => _brew(context),
              icon: const Icon(Icons.coffee_maker_outlined),
              label: Text(s.brewWithBean),
            ),
          ),
        ],
      ],
    );
  }
}

/// Thaws the grams of [portion] the user picks and opens a new brew of
/// [coffee] with them as the dose; [note] says why when the user did not
/// ask to thaw.
Future<void> _thawThenBrew(
  BuildContext context,
  JournalActions actions,
  JournalData data,
  Coffee coffee,
  FrozenPortion portion, {
  String? note,
}) async {
  final grams = await showThawDialog(context, portion, note: note);
  if (grams == null) return;
  if (!context.mounted) return;
  Navigator.pop(context);
  await actions.openBrewForm(
    data.coffees,
    initialCoffeeId: coffee.id,
    initialLotId: portion.lotId,
    initialDoseGrams: grams,
    initialFrozenSource: FrozenBrewSource(
      portionId: portion.id,
      lotId: portion.lotId,
      grams: grams,
    ),
  );
}

/// Asks which of several frozen portions to thaw, the oldest first.
Future<FrozenPortion?> _choosePortion(
  BuildContext context,
  List<FrozenPortion> portions,
) {
  final s = AppLocalizations.of(context)!;
  final locale = regionalLocale;
  return showDialog<FrozenPortion>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      key: const ValueKey('choose-portion'),
      title: Text(s.thawWhichPortion),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(s.onlyFrozenLeft),
        ),
        for (final portion in portions)
          SimpleDialogOption(
            key: ValueKey('choose-portion-${portion.id}'),
            onPressed: () => Navigator.pop(dialogContext, portion),
            child: Text(
              s.frozenPortionOption(
                portion.label,
                formatGrams(portion.remainingGrams, regionalLocale.toString()),
                switch (DateTime.tryParse(portion.frozenDate)) {
                  final date? => formatRegionalDate(date, locale),
                  null => portion.frozenDate,
                },
              ),
            ),
          ),
      ],
    ),
  );
}

/// Frozen portions with freeze, thaw, edit and delete.
class _FreezerSection extends StatefulWidget {
  const _FreezerSection({
    required this.actions,
    required this.coffee,
    required this.data,
    required this.stock,
  });

  final JournalActions actions;
  final Coffee coffee;
  final JournalData data;
  final CoffeeStock stock;

  @override
  State<_FreezerSection> createState() => _FreezerSectionState();
}

class _FreezerSectionState extends State<_FreezerSection> {
  JournalActions get actions => widget.actions;
  JournalRepository get repository => widget.actions.repository;

  Future<void> _freeze() async {
    final s = AppLocalizations.of(context)!;
    final labels = await showFreezeSheet(
      context,
      repository,
      lots: widget.stock.lots,
    );
    if (labels != null) {
      actions.message(
        labels.length == 1
            ? s.frozenSaved(labels.single)
            : s.frozenBatchSaved(labels.length),
      );
    }
  }

  /// Thaws grams the user picks; returns them, or null when cancelled or
  /// failed.
  Future<double?> _thaw(FrozenPortion portion) async {
    final s = AppLocalizations.of(context)!;
    final grams = await showThawDialog(context, portion);
    if (grams == null) return null;
    try {
      await repository.thawCoffee(portion.id, grams);
      return grams;
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
      return null;
    }
  }

  Future<void> _thawAndBrew(FrozenPortion portion) =>
      _thawThenBrew(context, actions, widget.data, widget.coffee, portion);

  Future<void> _edit(FrozenPortion portion) async {
    final lot = await repository.coffeeLot(portion.lotId);
    if (lot == null || !mounted) return;
    await showFreezeSheet(context, repository, lots: [lot], existing: portion);
  }

  Future<void> _delete(FrozenPortion portion) async {
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${s.deleteFrozenPortion} ${portion.label}'),
        content: portion.remainingGrams > 0
            ? Text(
                s.deleteFrozenPortionWarning(
                  formatGrams(
                    portion.remainingGrams,
                    regionalLocale.toString(),
                  ),
                ),
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.deleteFrozenPortion(portion.id);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final stock = widget.stock;
    final active = widget.coffee.archivedAtMs == null;
    final canFreeze =
        active && stock.lots.any((lot) => (unfrozenGrams(lot) ?? 0) > 0);
    if (!canFreeze && stock.frozen.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        // A section title like the others, with its action underneath.
        Semantics(
          header: true,
          child: Text(
            s.freezer,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (canFreeze) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              key: const ValueKey('freeze-coffee-button'),
              onPressed: _freeze,
              icon: const Icon(Icons.ac_unit_rounded),
              label: Text(s.freezeCoffee),
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final portion in stock.frozen)
          FrozenPortionCard(
            portion: portion,
            roastDate: stock.roastDateOf(portion),
            onThaw: () async {
              final grams = await _thaw(portion);
              if (grams != null) {
                actions.message(
                  s.thawedSaved(formatGrams(grams, regionalLocale.toString())),
                );
              }
            },
            onThawAndBrew: active ? () => _thawAndBrew(portion) : null,
            onEdit: () => _edit(portion),
            onDelete: () => _delete(portion),
          ),
      ],
    );
  }
}

/// Each origin's country, region, farm, producer, altitude, variety,
/// process and harvest.
class _OriginRows extends StatelessWidget {
  const _OriginRows({required this.components});

  final List<CoffeeComponent> components;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, origin) in components.indexed) ...[
          if (components.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                s.originNumber(index + 1),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          if (origin.country case final country?)
            DetailRow(
              s.country,
              [?coffeeCountryFor(country)?.flag, country].join(' '),
            ),
          if (origin.region case final region?) DetailRow(s.region, region),
          if (origin.farm case final farm?) DetailRow(s.farm, farm),
          if (origin.producer case final producer?)
            DetailRow(s.producer, producer),
          if (altitudeLabel(origin.altitudeMeters, origin.altitudeMaxMeters)
              case final altitude?)
            DetailRow(s.altitudeHeading, altitude),
          if (origin.variety case final variety?) DetailRow(s.variety, variety),
          if (origin.process case final process?) DetailRow(s.process, process),
          if (origin.harvest case final harvest?) DetailRow(s.harvest, harvest),
        ],
      ],
    );
  }
}

/// The three latest brews of the coffee, opening their details.
class _RecentBrews extends StatelessWidget {
  const _RecentBrews({
    required this.actions,
    required this.coffee,
    required this.data,
    required this.brews,
  });

  final JournalActions actions;
  final Coffee coffee;
  final JournalData data;

  /// Newest first.
  final List<Brew> brews;

  @override
  Widget build(BuildContext context) {
    if (brews.isEmpty) return const SizedBox.shrink();
    final s = AppLocalizations.of(context)!;
    final deviceLocale = regionalLocale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        SectionTitle(s.recentBrews),
        for (final brew in brews.take(3))
          Card(
            key: ValueKey('bean-recent-brew-${brew.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              // The recipe whole on its own line; method and date below.
              title: Text(
                brewRecipeLine(
                      brew,
                      actions.methods,
                      regionalLocale.toString(),
                      hidden: actions.hiddenParameters,
                    ) ??
                    brew.methodName,
              ),
              subtitle: Text(
                [
                  brew.methodName,
                  formatBrewTimestamp(brew, deviceLocale),
                  if (brew.archivedAtMs != null) s.archivedStatus,
                ].join(', '),
              ),
              trailing: switch (brew.rating) {
                final rating? => RatingBadge(
                  rating: rating,
                  localeName: regionalLocale.toString(),
                  semanticLabel:
                      '${s.rating}: ${NumberFormat('0.#', regionalLocale.toString()).format(rating)} / 10',
                ),
                null => const Icon(Icons.chevron_right_rounded),
              },
              onTap: () => actions.showBrewDetails(brew, coffee, data),
            ),
          ),
        if (brews.length > 3)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('bean-see-all-brews'),
              onPressed: () {
                Navigator.pop(context);
                actions.showBrewsOfCoffee(coffee);
              },
              child: Text(s.seeAllBrews(brews.length)),
            ),
          ),
      ],
    );
  }
}
