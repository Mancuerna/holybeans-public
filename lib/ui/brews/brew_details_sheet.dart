import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';
import 'package:holybeans/ui/brews/espresso_map_page.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/brews/sensory_map_page.dart';
import 'package:holybeans/ui/brews/stock_review_card.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/formatters.dart';
import 'package:holybeans/ui/core/photo_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:intl/intl.dart';

/// Opens the bottom sheet with everything recorded for [brew].
void showBrewDetailsSheet(
  BuildContext context,
  JournalActions actions,
  Brew brew,
  Coffee? coffee,
  JournalData data,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => BrewDetailsSheet(
    actions: actions,
    brew: brew,
    coffee: coffee,
    data: data,
  ),
);

/// Everything recorded for [brew]: recipe and results, cost, tasting,
/// equipment and notes, with rate, edit, share and repeat. Parameters
/// hidden in Settings stay out until the user reveals them.
class BrewDetailsSheet extends StatefulWidget {
  const BrewDetailsSheet({
    super.key,
    required this.actions,
    required this.brew,
    required this.coffee,
    required this.data,
  });

  final JournalActions actions;
  final Brew brew;
  final Coffee? coffee;
  final JournalData data;

  @override
  State<BrewDetailsSheet> createState() => _BrewDetailsSheetState();
}

class _BrewDetailsSheetState extends State<BrewDetailsSheet> {
  bool loading = false;
  Object? loadError;
  @override
  void initState() {
    super.initState();
    if (widget.data.reads != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final full = await widget.actions.repository.brew(widget.brew.id);
      if (full == null) throw StateError('Brew no longer exists');
      if (mounted) {
        setState(() {
          brew = full;
          loading = false;
        });
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() {
          loadError = error;
          loading = false;
        });
      }
    }
  }

  bool reveal = false;
  late bool favorite = widget.brew.isFavorite;

  Future<void> _toggleFavorite() async {
    final next = !favorite;
    // A message would hide behind the sheet; the star and the note below
    // the header say it here.
    final saved = await actions.setBrewFavorite(
      brew,
      favorite: next,
      announce: false,
    );
    if (saved && mounted) {
      setState(() => favorite = next);
    }
  }

  // Asked once, so revealing hidden values does not reload them.
  late final Stream<List<String>> photos = widget.actions.repository
      .watchBrewPhotos(widget.brew.id);
  late final Future<({ShotCurve curve, String source})?> curve = widget
      .actions
      .repository
      .brewCurve(widget.brew.id);

  /// The brew shown; blooms and pours saved from its curve update it here.
  late Brew brew = widget.brew;
  JournalActions get actions => widget.actions;

  bool shows(BrewParameter? parameter) =>
      reveal ||
      parameter == null ||
      !actions.hiddenParameters.contains(parameter);

  /// Closes the sheet, then runs [action] from the screen below.
  void _closeThen(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  /// The map for the brew's EY and TDS: the sensory map (a study of drip
  /// coffee) for filter, the espresso map, with its ratio, for espresso.
  Widget? _extractionMap(BuildContext context, BrewMethod? method) {
    final s = AppLocalizations.of(context)!;
    final ey = brewExtractionYield(brew);
    final tds = brew.tdsPercent;
    if (ey == null || !ey.isFinite || ey <= 0) return null;
    if (tds == null || !tds.isFinite || tds <= 0) return null;
    final espresso = isEspressoMethod(
      category: method?.category,
      methodName: method?.name ?? brew.methodName,
    );
    final ratio = switch ((brew.beverageGrams, brew.doseGrams)) {
      (final beverage?, final dose?) when dose > 0 => beverage / dose,
      _ => null,
    };
    if (espresso && ratio == null) return null;
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));
    return espresso
        ? TextButton.icon(
            key: const ValueKey('open-espresso-map-button'),
            onPressed: () => open(
              EspressoMapPage(eyPercent: ey, tdsPercent: tds, ratio: ratio!),
            ),
            icon: const Icon(Icons.grid_view_rounded),
            label: Text(s.openEspressoMap),
          )
        : TextButton.icon(
            key: const ValueKey('open-sensory-map-button'),
            onPressed: () =>
                open(SensoryMapPage(eyPercent: ey, tdsPercent: tds)),
            icon: const Icon(Icons.scatter_plot_rounded),
            label: Text(s.openSensoryMap),
          );
  }

  /// Favourite, rate, edit and share.
  List<Widget> _headerActions(AppLocalizations s, Coffee? coffee) => [
    if (brew.methodId != null)
      IconButton(
        key: const ValueKey('brew-detail-favorite'),
        tooltip: favorite ? s.unmarkFavoriteRecipe : s.markFavoriteRecipe,
        isSelected: favorite,
        icon: const Icon(Icons.favorite_border_rounded),
        selectedIcon: const Icon(Icons.favorite_rounded),
        onPressed: _toggleFavorite,
      ),
    IconButton(
      key: const ValueKey('brew-detail-rate'),
      tooltip: s.rateBrew,
      icon: const Icon(Icons.rate_review_outlined),
      onPressed: () => _closeThen(() => actions.rateBrew(brew, coffee)),
    ),
    IconButton(
      key: const ValueKey('brew-detail-edit'),
      tooltip: s.editBrew,
      icon: const Icon(Icons.edit_outlined),
      onPressed: () => _closeThen(
        () => actions.openBrewForm(widget.data.coffees, existing: brew),
      ),
    ),
    IconButton(
      key: const ValueKey('brew-detail-share'),
      tooltip: s.shareText,
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: coffee == null
          ? null
          : () => _closeThen(
              () => actions.shareBrew(
                brew,
                coffee,
                widget.data.componentsOf(coffee.id),
              ),
            ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (loading || loadError != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: loading
              ? const CircularProgressIndicator()
              : TextButton(
                  onPressed: _load,
                  child: Text(AppLocalizations.of(context)!.dataError),
                ),
        ),
      );
    }

    final s = AppLocalizations.of(context)!;
    final coffee = widget.coffee;
    final method = actions.methods
        .where((row) => row.id == brew.methodId)
        .firstOrNull;
    final pours = BrewPours.fromStorage(
      bloomCount: brew.bloomCount,
      pourCount: brew.pourCount,
      phasesJson: brew.pourPhasesJson,
    );
    final stats = _brewStats(
      s,
      brew,
      method,
      cost: coffee == null
          ? null
          : brewCost(brew, pricePerKgByCoffee([coffee], actions.latestLots)),
    );
    final hidden = actions.hiddenParameters;
    final hiddenCount =
        stats.where((entry) => hidden.contains(entry.$1)).length +
        _recordedRows(brew, pours).where(hidden.contains).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: DetailSheetContent(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailHeader(
                  title: coffee?.name ?? '—',
                  onTitleTap: coffee == null
                      ? null
                      : () => actions.showCoffeeDetails(coffee, widget.data),
                  subtitle: [
                    brew.methodName,
                    formatBrewTimestamp(brew, regionalLocale),
                    if (brew.archivedAtMs != null) s.archivedStatus,
                  ].join(', '),
                  actions: _headerActions(s, coffee),
                ),
                if (brew.stockReviewPending == true)
                  StockReviewCard(
                    repository: actions.repository,
                    brew: brew,
                    onResolved: (updated) {
                      if (mounted) setState(() => brew = updated);
                    },
                  ),
                if (favorite) _FavoriteNote(methodName: brew.methodName),
                _EquipmentRows(brew: brew, shows: shows),
                const SizedBox(height: 16),
                StatGrid(
                  minimumTileWidth: 140,
                  items: [
                    for (final (parameter, item) in stats)
                      if (shows(parameter)) item,
                  ],
                ),
                if (hiddenCount > 0)
                  _RevealHiddenButton(
                    count: hiddenCount,
                    revealed: reveal,
                    onPressed: () => setState(() => reveal = !reveal),
                  ),
                if (pours.phases.isNotEmpty && shows(BrewParameter.pourDetails))
                  BrewPourDetails(pours: pours, doseGrams: brew.doseGrams),
                // Counts copied from a repeated brew come without details: the
                // curve can still give them.
                if (pours.phases.isEmpty &&
                    !isEspressoMethod(
                      category: method?.category,
                      methodName: brew.methodName,
                    ))
                  _PoursFromCurve(
                    curve: curve,
                    brew: brew,
                    onSave: (found) async {
                      await actions.repository.setBrewPours(brew.id, found);
                      final saved = await actions.repository.brew(brew.id);
                      if (saved == null || !mounted) return;
                      setState(() => brew = saved);
                    },
                  ),
                if (_extractionMap(context, method) case final map?) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: map),
                ],
                _TastingSection(brew: brew),
                if (brew.notes?.trim() case final notes?
                    when notes.isNotEmpty && shows(BrewParameter.notes))
                  DetailRow(s.notes, notes, stacked: true),
                if (actions.photos case final store?
                    when shows(BrewParameter.photos))
                  StreamBuilder<List<String>>(
                    stream: photos,
                    builder: (context, snapshot) =>
                        switch (snapshot.data ?? const []) {
                          [] => const SizedBox.shrink(),
                          final files => Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: DetailPhotos(
                              store: store,
                              files: files,
                              label: s.brewPhoto,
                            ),
                          ),
                        },
                  ),
                _CurveSection(
                  espresso: isEspressoMethod(
                    category: method?.category,
                    methodName: brew.methodName,
                  ),
                  curve: curve,
                  firstDripMs: brew.firstDripSeconds == null
                      ? null
                      : brew.firstDripSeconds! * 1000,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('brew-detail-repeat'),
                    onPressed: () => _closeThen(
                      () => actions.openBrewForm(
                        widget.data.coffees,
                        seed: brew,
                        repeat: true,
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(s.repeatBrew, textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('brew-detail-compare'),
                    onPressed: () => _closeThen(
                      () => actions.compareBrew(brew, widget.data),
                    ),
                    icon: const Icon(Icons.compare_arrows_rounded),
                    label: Text(
                      s.compareBrewAction,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Says this brew is the favourite recipe of its coffee and method.
class _FavoriteNote extends StatelessWidget {
  const _FavoriteNote({required this.methodName});

  final String methodName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        key: const ValueKey('brew-detail-favorite-note'),
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.favoriteRecipeNote(methodName),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows or hides the values of parameters hidden in Settings.
class _RevealHiddenButton extends StatelessWidget {
  const _RevealHiddenButton({
    required this.count,
    required this.revealed,
    required this.onPressed,
  });

  final int count;
  final bool revealed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('brew-detail-hidden'),
        onPressed: onPressed,
        icon: Icon(
          revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        label: Text(
          '${s.hiddenDataCount(count)}, '
          '${revealed ? s.hideHiddenData : s.showHiddenData}',
        ),
      ),
    );
  }
}

/// The recorded values of [brew] as tiles, each with the parameter that
/// can hide it (none for the cost). Recipe first, then timing, pours and
/// results; cost and rating last. Espresso reads its three shot times
/// together before temperature and pressure; filter keeps temperature with
/// the recipe.
List<(BrewParameter?, StatItem)> _brewStats(
  AppLocalizations s,
  Brew brew,
  BrewMethod? method, {
  double? cost,
}) {
  final number = NumberFormat('0.#', regionalLocale.toString());
  final ratio = formatBrewRatio(
    methodCategory: method?.category,
    methodName: method?.name ?? brew.methodName,
    doseGrams: brew.doseGrams,
    waterGrams: brew.waterGrams,
    beverageGrams: brew.beverageGrams,
    localeName: regionalLocale.toString(),
  );
  final ey = brewExtractionYield(brew);
  final grindSetting = brew.grindSetting?.trim();
  String grams(double value) => formatGrams(value, regionalLocale.toString());
  final recipe = [
    if (brew.doseGrams case final dose?)
      (BrewParameter.dose, StatItem(s.dose, grams(dose))),
    if (!brew.isPreGround && grindSetting != null && grindSetting.isNotEmpty)
      (BrewParameter.grindSetting, StatItem(s.grindSetting, grindSetting)),
    if (brew.waterGrams case final water?)
      (BrewParameter.water, StatItem(s.water, grams(water))),
    if (brew.beverageGrams case final beverage?)
      (BrewParameter.beverage, StatItem(s.brewOutput, grams(beverage))),
    if (ratio != null) (BrewParameter.ratio, StatItem(s.ratio, ratio)),
  ];
  final timing = [
    if (brew.timeSeconds case final seconds?)
      (BrewParameter.time, StatItem(s.timeShort, formatDuration(seconds))),
    if (brew.preinfusionSeconds case final seconds?)
      (BrewParameter.preinfusion, StatItem(s.preinfusion, '$seconds s')),
    if (brew.firstDripSeconds case final seconds?)
      (BrewParameter.firstDrip, StatItem(s.firstDrip, '$seconds s')),
  ];
  final conditions = [
    if (brew.temperatureC case final celsius?)
      (
        BrewParameter.temperature,
        StatItem(s.temperature, '${number.format(celsius)} °C'),
      ),
    if (brew.pressureBar case final bar?)
      (
        BrewParameter.pressure,
        StatItem(s.pressure, '${number.format(bar)} bar'),
      ),
  ];
  final espresso = isEspressoMethod(
    category: method?.category,
    methodName: method?.name ?? brew.methodName,
  );
  return [
    ...recipe,
    if (espresso) ...[
      ...timing,
      ...conditions,
    ] else ...[
      ...conditions,
      ...timing,
    ],
    if (brew.bloomCount case final count?)
      (BrewParameter.bloomCount, StatItem(s.bloomCount, '$count')),
    if (brew.bloomSeconds case final seconds?)
      (BrewParameter.bloom, StatItem(s.bloomTime, '$seconds s')),
    if (brew.pourCount case final count?)
      (BrewParameter.pourCount, StatItem(s.pourCount, '$count')),
    if (brew.brix case final bx?)
      (BrewParameter.tds, StatItem(s.brix, '$bx °Bx · × ${brew.brixFactor}')),
    if (brew.tdsPercent case final tds?)
      (
        BrewParameter.tds,
        StatItem(
          brew.brix != null ? s.estimatedTds : s.tds,
          '${NumberFormat('0.##', regionalLocale.toString()).format(tds)} %',
        ),
      ),
    if (ey != null)
      (
        BrewParameter.ey,
        StatItem(
          brew.brix != null ? '${s.ey} ≈' : s.ey,
          '${NumberFormat('0.0', regionalLocale.toString()).format(ey)} %',
        ),
      ),
    if (cost != null)
      (null, StatItem(s.brewCost, formatEuro(cost, regionalLocale.toString()))),
    if (brew.rating case final rating?)
      (
        BrewParameter.rating,
        StatItem(s.rating, '${number.format(rating)} / 10'),
      ),
  ];
}

/// Parameters [brew] has a value for outside the tile grid.
Set<BrewParameter> _recordedRows(Brew brew, BrewPours pours) {
  final grinderName = brew.grinderName?.trim() ?? '';
  return {
    if (grinderName.isNotEmpty || brew.isPreGround) BrewParameter.grinder,
    if (!brew.isPreGround && brew.grindRpm != null) BrewParameter.grindRpm,
    if (!brew.isPreGround && brew.feederRpm != null) BrewParameter.feederRpm,
    if (brew.profileName != null) BrewParameter.profile,
    if (brew.waterProfileName != null) BrewParameter.waterProfile,
    if (brew.notes?.trim().isNotEmpty ?? false) BrewParameter.notes,
    if (pours.phases.isNotEmpty) BrewParameter.pourDetails,
  };
}

/// Blooms and pours found on the brew's curve, offered to be saved when
/// none are recorded.
class _PoursFromCurve extends StatelessWidget {
  const _PoursFromCurve({
    required this.curve,
    required this.brew,
    required this.onSave,
  });

  final Future<({ShotCurve curve, String source})?> curve;
  final Brew brew;
  final Future<void> Function(BrewPours pours) onSave;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({ShotCurve curve, String source})?>(
        future: curve,
        builder: (context, snapshot) {
          final found = switch (snapshot.data) {
            (:final curve, source: _) => poursToFill(
              curve,
              doseGrams: brew.doseGrams,
              bloomCount: brew.bloomCount,
              pourCount: brew.pourCount,
            ),
            null => null,
          };
          if (found == null) return const SizedBox.shrink();
          final s = AppLocalizations.of(context)!;
          final colors = Theme.of(context).colorScheme;
          return Card(
            key: const ValueKey('brew-detail-pours-from-curve'),
            margin: const EdgeInsets.only(top: 12),
            color: colors.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.curveShowsPours(
                        found.bloomCount ?? 0,
                        found.pourCount ?? 0,
                      ),
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('brew-detail-pours-save'),
                    onPressed: () => onSave(found),
                    child: Text(s.save),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// The saved extraction curve, if the brew has one.
class _CurveSection extends StatelessWidget {
  const _CurveSection({
    required this.curve,
    required this.espresso,
    this.firstDripMs,
  });

  final bool espresso;

  final Future<({ShotCurve curve, String source})?> curve;
  final int? firstDripMs;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({ShotCurve curve, String source})?>(
        future: curve,
        builder: (context, snapshot) => switch (snapshot.data) {
          (:final curve, :final source) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    AppLocalizations.of(context)!.extractionCurve,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                ExtractionChart(
                  curve: curve,
                  firstDripMs: firstDripMs,
                  showFlowStatistics: espresso,
                  // Scales, and BeanConqueror, weigh the flow.
                  flowUnit: source == ImportOperations.meticulousSource
                      ? 'ml/s'
                      : 'g/s',
                ),
              ],
            ),
          ),
          null => const SizedBox.shrink(),
        },
      );
}

/// The taste compass and flavour radar, when the brew was tasted.
class _TastingSection extends StatelessWidget {
  const _TastingSection({required this.brew});

  final Brew brew;

  @override
  Widget build(BuildContext context) {
    final tasting = BrewTasting.of(brew);
    if (tasting.isEmpty) return const SizedBox.shrink();
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            s.tasting,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if ((brew.tasteBalance, brew.tasteStrength) case (
          final balance?,
          final strength?,
        )) ...[
          const SizedBox(height: 6),
          Text(
            compassLabel(s, balance, strength),
            key: const ValueKey('brew-detail-compass'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(compassAdvice(s, balance, strength)!),
        ],
        if (tasting.scores.any((score) => score != null)) ...[
          const SizedBox(height: 8),
          Center(child: FlavorRadar(scores: tasting.scores)),
        ],
      ],
    );
  }
}

/// Grinder, machine and water profiles, each shown only when
/// recorded and not hidden. The grind setting follows in the figures.
class _EquipmentRows extends StatelessWidget {
  const _EquipmentRows({required this.brew, required this.shows});

  final Brew brew;
  final bool Function(BrewParameter parameter) shows;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final grinderName = brew.grinderName?.trim() ?? '';
    final grinder = [
      if (grinderName.isNotEmpty && shows(BrewParameter.grinder)) grinderName,
      if (brew.grindRpm != null && shows(BrewParameter.grindRpm))
        '${brew.grindRpm} RPM',
      if (brew.feederRpm != null && shows(BrewParameter.feederRpm))
        '${s.feederRpm}: ${brew.feederRpm}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (brew.isPreGround) ...[
          if (shows(BrewParameter.grinder)) DetailRow(s.grinder, s.preGround),
        ] else if (grinder.isNotEmpty)
          // The grind setting follows in the recipe figures.
          DetailRow(s.grinder, grinder.join(', ')),
        if (brew.profileName case final profile?
            when shows(BrewParameter.profile))
          DetailRow(s.profileName, profile),
        if (brew.recipientName != null &&
            brew.recipientGrams != null &&
            (brew.recipientIsPortafilter || shows(BrewParameter.beverage)))
          DetailRow(
            brew.recipientIsPortafilter ? s.portafilter : s.recipient,
            '${brew.recipientName} · ${NumberFormat('0.#', regionalLocale.toString()).format(brew.recipientGrams)} g',
          ),
        if (brew.waterProfileName case final water?
            when shows(BrewParameter.waterProfile))
          DetailRow(s.waterProfile, water),
      ],
    );
  }
}
