import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:intl/intl.dart';

class WaterProfileCard extends StatelessWidget {
  const WaterProfileCard({
    super.key,
    required this.profile,
    required this.onEdit,
    required this.onArchive,
    required this.onCalculate,
    this.onDelete,
    this.onRecipe,
  });

  final WaterProfile profile;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onCalculate;
  final VoidCallback? onDelete;
  final VoidCallback? onRecipe;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        profile.name,
                        // Like the titles of the other equipment cards.
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  _menu(s),
                ],
              ),
              _WaterSummary(profile: profile),
              if (profile.notes?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    profile.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (profile.archivedAtMs != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.archivedStatus),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(AppLocalizations strings) => PopupMenuButton<String>(
    tooltip: strings.actions,
    onSelected: (value) {
      switch (value) {
        case 'edit':
          onEdit();
        case 'calculate':
          onCalculate();
        case 'recipe':
          onRecipe?.call();
        case 'delete':
          onDelete?.call();
        default:
          onArchive();
      }
    },
    itemBuilder: (context) => [
      PopupMenuItem(value: 'edit', child: Text(strings.editWaterProfile)),
      PopupMenuItem(value: 'calculate', child: Text(strings.waterUseInitial)),
      if (onRecipe != null)
        PopupMenuItem(value: 'recipe', child: Text(strings.waterRecipeOpen)),
      PopupMenuItem(
        value: 'archive',
        child: Text(
          profile.archivedAtMs == null
              ? strings.archiveWaterProfile
              : strings.restoreWaterProfile,
        ),
      ),
      if (onDelete != null)
        PopupMenuItem(value: 'delete', child: Text(strings.deleteWaterProfile)),
    ],
  );
}

class _WaterSummary extends StatelessWidget {
  const _WaterSummary({required this.profile});
  final WaterProfile profile;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    final number = NumberFormat('0.##', regionalLocale.toString());
    final ions = compositionOf(profile).ions;
    final hasMinerals = ions.values.any((value) => value != null);
    final added = addedPotassiumOf(profile);
    final metrics = [
      if (profile.ghPpmAsCaCO3 case final value?)
        _HeadlineValue(
          label: s.waterGhAxis,
          value: number.format(value),
          semantics: s.waterHardness,
        ),
      if (profile.khPpmAsCaCO3 case final value?)
        _HeadlineValue(
          label: s.waterKhAxis,
          value: number.format(value),
          semantics: s.waterAlkalinity,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            230;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ValueColumns(twoColumns: twoColumns, children: metrics),
              const SizedBox(height: 6),
              Text(s.waterSummaryUnits, style: small),
            ],
            if (profile.tdsPpm != null || profile.ph != null) ...[
              const SizedBox(height: 12),
              _ValueColumns(
                twoColumns: twoColumns,
                children: [
                  if (profile.tdsPpm case final value?)
                    _MineralValue(
                      label: s.waterSummaryTds,
                      value: number.format(value),
                    ),
                  if (profile.ph case final value?)
                    _MineralValue(
                      label: s.waterSummaryPh,
                      value: number.format(value),
                    ),
                ],
              ),
            ],
            if (hasMinerals || added != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                key: PageStorageKey('water-composition-${profile.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(s.waterCompositionSummary, style: small),
                children: [
                  if (hasMinerals) ...[
                    _ValueColumns(
                      twoColumns: twoColumns,
                      children: [
                        for (final ion in WaterIon.values)
                          _MineralValue(
                            key: ValueKey('water-ion-${ion.name}'),
                            label: ionSymbol(ion),
                            value: ions[ion] == null
                                ? '—'
                                : number.format(ions[ion]),
                            semantics:
                                '${ionLabel(s, ion)}: ${ions[ion] == null ? s.waterUnknown : number.format(ions[ion])}',
                          ),
                      ],
                    ),
                    if (ions.values.any((value) => value == null))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(s.waterSummaryMissing, style: small),
                      ),
                  ],
                  if (added != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.waterPotassiumAdded(number.format(added)),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(s.waterPotassiumTotalUnknown, style: small),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ValueColumns extends StatelessWidget {
  const _ValueColumns({required this.children, required this.twoColumns});
  final List<Widget> children;
  final bool twoColumns;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index += twoColumns ? 2 : 1)
        Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
          child: twoColumns && index + 1 < children.length
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children[index]),
                    const SizedBox(width: 16),
                    Expanded(child: children[index + 1]),
                  ],
                )
              : children[index],
        ),
    ],
  );
}

class _HeadlineValue extends StatelessWidget {
  const _HeadlineValue({
    required this.label,
    required this.value,
    required this.semantics,
  });
  final String label;
  final String value;
  final String semantics;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$semantics: $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineralValue extends StatelessWidget {
  const _MineralValue({
    super.key,
    required this.label,
    required this.value,
    this.semantics,
  });
  final String label;
  final String value;
  final String? semantics;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semantics,
      excludeSemantics: semantics != null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
