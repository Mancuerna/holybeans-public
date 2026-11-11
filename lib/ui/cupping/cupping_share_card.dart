import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/cupping/cupping_scores.dart';
import 'package:intl/intl.dart';

class CuppingShareCard extends StatelessWidget {
  const CuppingShareCard({
    super.key,
    required this.data,
    this.includeNotes = true,
    this.dark = false,
  });
  final CuppingShareData data;
  final bool includeNotes;
  final bool dark;

  @override
  Widget build(BuildContext context) => Theme(
    data: dark ? AppTheme.dark() : AppTheme.light(),
    child: MediaQuery.withNoTextScaling(child: Builder(builder: _build)),
  );

  Widget _build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(
      data.session.startedAtMs ?? data.session.createdAtMs,
    );
    return Container(
      key: const ValueKey('cupping-share-card'),
      width: 720,
      padding: const EdgeInsets.all(36),
      color: colors.surfaceContainerLowest,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: AppTheme.text,
          fontSize: 18,
          height: 1.4,
          color: colors.onSurface,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.coffee_rounded, color: colors.primary, size: 28),
                const SizedBox(width: 8),
                const Text(
                  'HolyBeans',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  s.cuppingShareCupCount(data.cups.length),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (data.blind) ...[
              Text(s.cuppingBlind, style: TextStyle(color: colors.primary)),
              const SizedBox(height: 8),
            ],
            Text(
              data.session.name.isEmpty ? s.cuppingTitle : data.session.name,
              style: const TextStyle(
                fontSize: 40,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${DateFormat.yMMMd(regionalLocale.toString()).format(date)} · ${s.cuppingTitle}',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 20),
            ),
            const SizedBox(height: 28),
            if (data.commonRecipe) ...[
              _Recipe(brew: data.cups.first.brew!),
              const SizedBox(height: 26),
            ] else ...[
              Text(
                s.cuppingShareIndividualRecipe,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],
            for (var i = 0; i < data.cups.length; i += 2) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _CupCard(
                        cup: data.cups[i],
                        includeNotes: includeNotes,
                        recipe: !data.commonRecipe,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: i + 1 < data.cups.length
                          ? _CupCard(
                              cup: data.cups[i + 1],
                              includeNotes: includeNotes,
                              recipe: !data.commonRecipe,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.cuppingShareProfile,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  s.cuppingShareIntensities,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ScoreGrid(cups: data.cups),
            const SizedBox(height: 28),
            Divider(color: colors.outlineVariant, height: 1),
            const SizedBox(height: 16),
            Text(
              s.cuppingShareLegend,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CupCard extends StatelessWidget {
  const _CupCard({
    required this.cup,
    required this.includeNotes,
    required this.recipe,
  });
  final CuppingShareCup cup;
  final bool includeNotes;
  final bool recipe;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final brew = cup.brew;
    final grinder = cup.grinder?.name ?? brew?.grinderName;
    final water = cup.water?.name ?? brew?.waterProfileName;
    final origin = cup.components
        .map(
          (c) => [
            c.country,
            c.process,
          ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' · '),
        )
        .where((v) => v.isNotEmpty)
        .toSet()
        .join('\n');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.onSurface, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                color: colors.primary,
                child: Text(
                  cup.letter,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                brew?.rating == null
                    ? '—'
                    : formatDecimal(
                        brew!.rating,
                        pattern: '0.0',
                        locale: regionalLocale.toString(),
                      ),
                style: AppTheme.figures(
                  TextStyle(fontSize: 36, height: 1, color: colors.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, left: 3),
                child: Text(
                  '/ 10',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            brew == null
                ? s.cuppingDeletedCup
                : cup.coffee?.name ?? s.coffeeBlock,
            style: const TextStyle(
              fontSize: 23,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (brew != null) ...[
            if (cup.coffee?.roaster.isNotEmpty ?? false)
              _Muted(cup.coffee!.roaster),
            if (origin.isNotEmpty) _Muted(origin),
            Divider(color: colors.outlineVariant, height: 28),
            if (grinder?.trim().isNotEmpty ?? false)
              Text('${s.grinder}: $grinder'),
            if (brew.grindSetting?.trim().isNotEmpty ?? false)
              Text('${s.grindSetting}: ${brew.grindSetting}'),
            if (water?.trim().isNotEmpty ?? false)
              Text('${s.waterProfile}: $water'),
            if (recipe) ...[
              const SizedBox(height: 12),
              Text(_recipeText(brew, s), style: const TextStyle(fontSize: 16)),
            ],
            if (includeNotes && (brew.notes?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 14),
              Text(brew.notes!),
            ],
          ],
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

List<(String, String)> _recipeValues(Brew brew, AppLocalizations s) {
  final number = NumberFormat('0.##', regionalLocale.toString());
  String grams(double? v) => v == null ? '—' : '${number.format(v)} g';
  return [
    (s.dose, grams(brew.doseGrams)),
    (s.water, grams(brew.waterGrams)),
    (
      s.temperature,
      brew.temperatureC == null
          ? '—'
          : '${number.format(brew.temperatureC)} °C',
    ),
    (
      s.ratio,
      brew.doseGrams == null || brew.doseGrams! <= 0 || brew.waterGrams == null
          ? '—'
          : '1:${formatDecimal(brew.waterGrams! / brew.doseGrams!, pattern: '0.#', locale: regionalLocale.toString())}',
    ),
  ];
}

String _recipeText(Brew brew, AppLocalizations s) =>
    _recipeValues(brew, s).map((v) => '${v.$1}: ${v.$2}').join('\n');

class _Recipe extends StatelessWidget {
  const _Recipe({required this.brew});
  final Brew brew;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.onSurface, width: 2),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in _recipeValues(
            brew,
            AppLocalizations.of(context),
          ))
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: AppTheme.figures(const TextStyle(fontSize: 28)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ScoreGrid extends StatelessWidget {
  const _ScoreGrid({required this.cups});
  final List<CuppingShareCup> cups;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final labels = cuppingLabels(s);
    Widget cell(String value, {bool heading = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: heading
            ? const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)
            : AppTheme.figures(const TextStyle(fontSize: 25)),
      ),
    );
    return Table(
      columnWidths: const {0: FixedColumnWidth(156)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: colors.outlineVariant),
        top: BorderSide(color: colors.outlineVariant),
        bottom: BorderSide(color: colors.outlineVariant),
      ),
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(s.cuppingByCup),
            ),
            for (final cup in cups) cell(cup.letter, heading: true),
          ],
        ),
        for (var i = 0; i < labels.length; i++)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(labels[i])),
              for (final cup in cups) cell(cup.scores[i]?.toString() ?? '—'),
            ],
          ),
      ],
    );
  }
}
