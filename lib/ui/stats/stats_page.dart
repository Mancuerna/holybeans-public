import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_stats.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/stats/stats_brews_tab.dart';
import 'package:holybeans/ui/stats/stats_costs_tab.dart';
import 'package:holybeans/ui/stats/stats_tabs.dart';
import 'package:holybeans/ui/stats/stats_view_model.dart';
import 'package:holybeans/ui/year_review/year_review_page.dart';

/// Brewing statistics over a chosen period, in four tabs: an overview,
/// the coffees, the brews and the costs.
class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.coffees,
    required this.brews,
    required this.components,
    required this.methods,
    required this.remainingGrams,
    required this.frozenGrams,
    this.lots = const [],
    this.pricePerKg = const {},
    this.now,
    this.photos,
    this.photoOf,
  });

  final List<Coffee> coffees;
  final List<Brew> brews;
  final List<CoffeeComponent> components;
  final List<BrewMethod> methods;

  /// Every bag, for what was bought and when coffees were roasted.
  final List<CoffeeLot> lots;

  /// Coffee at hand now, fresh and frozen, whatever the period.
  final double remainingGrams;
  final double frozenGrams;

  /// Price per kilo by coffee ID, for the cost of the coffee used.
  final Map<String, double> pricePerKg;

  /// Fixed clock for tests.
  final DateTime? now;
  final PhotoStore? photos;
  final Future<String?> Function(Brew)? photoOf;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsRange range = StatsRange.all;
  final model = StatsViewModel();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didUpdateWidget(StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  void _prepare() => model.update((
    brews: widget.brews,
    coffees: widget.coffees,
    components: widget.components,
    methods: widget.methods,
    lots: widget.lots,
    prices: widget.pricePerKg,
    range: range,
    now: widget.now ?? DateUtils.dateOnly(DateTime.now()),
    language: AppLocalizations.of(context).localeName,
    remaining: widget.remainingGrams,
    frozen: widget.frozenGrams,
  ));
  void _setRange(StatsRange next) {
    setState(() => range = next);
    _prepare();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = widget.now ?? DateTime.now();
    final data = model.value;
    final rangeLabels = {
      StatsRange.week: (s.statsRangeWeekShort, s.statsRangeWeek),
      StatsRange.month: (s.statsRangeMonthShort, s.statsRangeMonth),
      StatsRange.quarter: (s.statsRangeQuarterShort, s.statsRangeQuarter),
      StatsRange.year: (s.statsRangeYearShort, s.statsRangeYear),
      StatsRange.all: (s.statsRangeAllShort, s.statsRangeAll),
    };
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.statsTitle),
          actions: [
            IconButton(
              key: const ValueKey('stats-year-review'),
              tooltip: s.yearReviewTitle,
              icon: const Icon(Icons.auto_awesome_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => YearReviewPage(
                    lots: widget.lots,
                    brews: widget.brews,
                    coffees: widget.coffees,
                    components: widget.components,
                    methods: widget.methods,
                    now: now,
                    photos: widget.photos,
                    photoOf: widget.photoOf,
                  ),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            key: const ValueKey('stats-tabs'),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s.statsTabOverview),
              Tab(text: s.statsTabBeans),
              Tab(text: s.statsTabBrews),
              Tab(text: s.statsTabCosts),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // One row for every tab: short labels, the full name as
                  // tooltip and for screen readers. Large text gets chips
                  // that wrap, as five segments would not fit.
                  if (MediaQuery.textScalerOf(context).scale(10) > 13)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final option in StatsRange.values)
                          ChoiceChip(
                            key: ValueKey('stats-range-${option.name}'),
                            label: Text(rangeLabels[option]!.$2),
                            selected: range == option,
                            onSelected: (_) => _setRange(option),
                          ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<StatsRange>(
                        key: const ValueKey('stats-range'),
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: [
                          for (final option in StatsRange.values)
                            ButtonSegment(
                              value: option,
                              tooltip: rangeLabels[option]!.$2,
                              label: Text(
                                rangeLabels[option]!.$1,
                                key: ValueKey('stats-range-${option.name}'),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                        ],
                        selected: {range},
                        onSelectionChanged: (value) => _setRange(value.single),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    s.statsIncludesArchived,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (data != null) ...[
              SizedBox(
                height: 4,
                child: model.updating
                    ? const LinearProgressIndicator(
                        key: ValueKey('stats-refreshing'),
                      )
                    : null,
              ),
              if (model.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      s.dataError,
                      key: const ValueKey('stats-refresh-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
            ],
            Expanded(
              child: data == null
                  ? Center(
                      child: model.error == null
                          ? const CircularProgressIndicator(
                              key: ValueKey('stats-preparing'),
                            )
                          : Text(s.dataError),
                    )
                  : TabBarView(
                      children: [
                        StatsOverviewTab(data: data),
                        StatsBeansTab(data: data),
                        StatsBrewsTab(data: data),
                        StatsCostsTab(data: data),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
