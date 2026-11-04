import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/equipment/equipment_delete.dart';
import 'package:holybeans/ui/equipment/water_calculator_page.dart';
import 'package:holybeans/ui/equipment/water_chart.dart';
import 'package:holybeans/ui/equipment/water_profile_card.dart';
import 'package:holybeans/ui/equipment/water_profile_form.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

/// Reusable water recipes used by brews, listed inside the equipment tab.
class WaterProfilesList extends StatefulWidget {
  const WaterProfilesList({
    super.key,
    required this.repository,
    required this.showArchived,
  });

  final JournalRepository repository;
  final bool showArchived;

  @override
  State<WaterProfilesList> createState() => _WaterProfilesListState();
}

class _WaterProfilesListState extends State<WaterProfilesList> {
  late final Stream<List<WaterProfile>> profiles = widget.repository
      .watchWaterProfiles(includeArchived: true);

  bool graph = false;
  bool references = true;

  Future<void> _edit(WaterProfile profile) async {
    final result = await showWaterProfileForm(
      context,
      widget.repository,
      existing: profile,
    );
    if (result != null && mounted) {
      _message(AppLocalizations.of(context)!.waterProfileSaved);
    }
  }

  Future<void> _archive(WaterProfile profile) async {
    final strings = AppLocalizations.of(context)!;
    try {
      await widget.repository.setWaterProfileArchived(
        profile.id,
        archived: profile.archivedAtMs == null,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(context, error, strings.saveFailed);
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return StreamBuilder<List<WaterProfile>>(
      stream: profiles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(strings.dataError));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final visible = snapshot.data!
            .where(
              (profile) => widget.showArchived || profile.archivedAtMs == null,
            )
            .toList();
        final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
        final header = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // A tool, not a heading: a row that reads as something
              // to open, with what it does.
              Expanded(
                child: Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    key: const ValueKey('open-water-calculator'),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 16,
                      end: 8,
                    ),
                    leading: const Icon(Icons.calculate_outlined),
                    title: Text(strings.waterCalculator),
                    // At large text the name alone says it.
                    subtitle: largeText
                        ? null
                        : Text(strings.waterCalculatorEntryHint),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        showWaterCalculator(context, widget.repository),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('toggle-water-graph'),
                tooltip: graph ? strings.waterList : strings.waterGraph,
                icon: Icon(graph ? Icons.list : Icons.scatter_plot_outlined),
                onPressed: () => setState(() => graph = !graph),
              ),
            ],
          ),
        );
        // At large text the header never takes more than part of a short
        // screen; if it does not fit there it scrolls instead of overflowing.
        return LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (largeText)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .45,
                  ),
                  child: SingleChildScrollView(child: header),
                )
              else
                header,
              Expanded(
                child: graph
                    ? _graph(visible, strings)
                    : _list(visible, strings),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(List<WaterProfile> visible, AppLocalizations s) {
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.showArchived ? s.noWaterProfiles : s.noActiveWaterProfiles,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => WaterProfileCard(
        profile: visible[index],
        onEdit: () => _edit(visible[index]),
        onArchive: () => _archive(visible[index]),
        onDelete: () => deleteEquipmentAfterConfirming(
          context,
          name: visible[index].name,
          check: () =>
              widget.repository.waterProfileDeletionBlockers(visible[index].id),
          delete: () =>
              widget.repository.deleteUnusedWaterProfile(visible[index].id),
        ),
        onCalculate: () => showWaterCalculator(
          context,
          widget.repository,
          initialWater: visible[index],
        ),
        onRecipe: visible[index].recipeJson == null
            ? null
            : () => showWaterCalculator(
                context,
                widget.repository,
                seed: WaterRecipe.fromJson(visible[index].recipeJson!),
              ),
      ),
    );
  }

  Widget _graph(List<WaterProfile> visible, AppLocalizations s) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(s.waterReferences),
        value: references,
        onChanged: (value) => setState(() => references = value),
      ),
      WaterChart(
        points: [
          for (final profile in visible)
            WaterChartPoint(
              id: profile.id,
              label: profile.name,
              water: compositionOf(profile),
            ),
          if (references)
            for (final preset in WaterPreset.values)
              WaterChartPoint(
                id: 'preset-${preset.name}',
                label: presetLabel(s, preset),
                water: preset.composition,
                kind: WaterPointKind.reference,
              ),
        ],
        onPoint: (point) async {
          final profile = visible.where((p) => p.id == point.id).firstOrNull;
          if (profile != null) {
            await _edit(profile);
          } else {
            final preset = WaterPreset.values.singleWhere(
              (p) => point.id == 'preset-${p.name}',
            );
            await showWaterCalculator(
              context,
              widget.repository,
              seed: WaterRecipe(
                litres: 1,
                calcium: CalciumForm.dihydrate,
                mode: WaterCalculationMode.preset,
                base: WaterComposition.distilled(),
                target: preset.composition,
                presetId: preset.name,
                grams: preset.gramsPerLitre(CalciumForm.dihydrate),
              ),
            );
          }
        },
      ),
    ],
  );
}

/// Opens the shared create/edit form and returns the saved profile.
