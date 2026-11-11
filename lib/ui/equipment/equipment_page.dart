import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/equipment_overview.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/journal_codes.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/cupping/cupping_sessions_page.dart';
import 'package:holybeans/ui/equipment/equipment_delete.dart';
import 'package:holybeans/ui/equipment/equipment_forms.dart';
import 'package:holybeans/ui/equipment/method_tools_sheet.dart';
import 'package:holybeans/ui/equipment/piston/piston_page.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';
import 'package:holybeans/ui/equipment/tools_page.dart';
import 'package:holybeans/ui/equipment/water_profiles_page.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';
import 'package:intl/intl.dart';

enum EquipmentSection {
  methods,
  grinders,
  tools,
  water,
  recipients,
  portafilters,
}

/// The equipment tab: brew methods, grinders and water profiles.
class EquipmentPage extends StatefulWidget {
  const EquipmentPage({
    super.key,
    required this.repository,
    required this.section,
    required this.onSectionChanged,
    required this.showArchived,
    this.onShowMethodBrews,
    this.onBrewWithMethod,
  });

  final JournalRepository repository;
  final EquipmentSection section;
  final ValueChanged<EquipmentSection> onSectionChanged;
  final bool showArchived;

  /// Opens the brew list filtered to a method name.
  final ValueChanged<BrewMethod>? onShowMethodBrews;

  /// Starts a new brew with a method preselected.
  final ValueChanged<BrewMethod>? onBrewWithMethod;

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage>
    with SingleTickerProviderStateMixin {
  late final Stream<List<BrewMethod>> methods = widget.repository.watchMethods(
    includeArchived: true,
  );
  late final Stream<List<Grinder>> grinders = widget.repository.watchGrinders(
    includeArchived: true,
  );

  /// Archived brews count too: a method's history includes them, as Stats
  /// does.
  late final brews = widget.repository.reads.watchEquipment();
  late final TabController tabs = TabController(
    length: EquipmentSection.values.length,
    initialIndex: widget.section.index,
    vsync: this,
  );
  bool get showArchived => widget.showArchived;

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      if (!tabs.indexIsChanging && tabs.index != widget.section.index) {
        widget.onSectionChanged(EquipmentSection.values[tabs.index]);
      }
    });
  }

  @override
  void didUpdateWidget(EquipmentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (tabs.index != widget.section.index) {
      tabs.index = widget.section.index;
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _editMethod(BrewMethod method) async {
    final saved = await showMethodForm(context, widget.repository, method);
    if (saved != null && mounted) {
      _message(AppLocalizations.of(context).methodSaved);
    }
  }

  Future<void> _editGrinder(Grinder grinder) async {
    final saved = await showGrinderForm(context, widget.repository, grinder);
    if (saved != null && mounted) {
      _message(AppLocalizations.of(context).grinderSaved);
    }
  }

  Future<void> _archiveMethod(BrewMethod method) async {
    final s = AppLocalizations.of(context);
    try {
      await widget.repository.setMethodArchived(
        method.id,
        archived: method.archivedAtMs == null,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  Future<void> _archiveGrinder(Grinder grinder) async {
    final s = AppLocalizations.of(context);
    try {
      await widget.repository.setGrinderArchived(
        grinder.id,
        archived: grinder.archivedAtMs == null,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final labels = [
      s.methods,
      s.grinders,
      s.methodTools,
      s.waterTab,
      s.recipients,
      s.portafilters,
    ];
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final style = Theme.of(context).textTheme.titleSmall!;
            final scale = MediaQuery.textScalerOf(context);
            final direction = Directionality.of(context);
            final scrollable = labels.asMap().entries.any((entry) {
              final painter = TextPainter(
                text: TextSpan(text: entry.value, style: style),
                textDirection: direction,
                textScaler: scale,
                maxLines: 1,
              )..layout();
              final tooWide =
                  painter.width > constraints.maxWidth / labels.length;
              painter.dispose();
              return tooWide;
            });
            return TabBar(
              key: const ValueKey('equipment-tabs'),
              controller: tabs,
              isScrollable: scrollable,
              tabAlignment: scrollable ? TabAlignment.start : null,
              labelPadding: scrollable
                  ? const EdgeInsets.symmetric(horizontal: 14)
                  : null,
              tabs: [for (final label in labels) Tab(text: label)],
            );
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (widget.section) {
            EquipmentSection.portafilters => RecipientsList(
              key: const ValueKey('portafilters-list'),
              repository: widget.repository,
              showArchived: showArchived,
              isPortafilter: true,
            ),
            EquipmentSection.recipients => RecipientsList(
              repository: widget.repository,
              showArchived: showArchived,
            ),
            EquipmentSection.tools => ToolsList(
              repository: widget.repository,
              showArchived: showArchived,
            ),
            EquipmentSection.water => WaterProfilesList(
              repository: widget.repository,
              showArchived: showArchived,
            ),
            _ => StreamBuilder<List<BrewMethod>>(
              stream: methods,
              builder: (context, methodSnapshot) =>
                  StreamBuilder<List<Grinder>>(
                    stream: grinders,
                    builder: (context, grinderSnapshot) {
                      if (methodSnapshot.hasError || grinderSnapshot.hasError) {
                        return Center(child: Text(s.dataError));
                      }
                      if (!methodSnapshot.hasData || !grinderSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return StreamBuilder<EquipmentOverview>(
                        stream: brews,
                        builder: (context, brewSnapshot) =>
                            brewSnapshot.hasError
                            ? Center(child: Text(s.dataError))
                            : !brewSnapshot.hasData
                            ? const Center(child: CircularProgressIndicator())
                            : _EquipmentSectionList(
                                repository: widget.repository,
                                section: widget.section,
                                methods: methodSnapshot.data!,
                                grinders: grinderSnapshot.data!,
                                usage:
                                    brewSnapshot.data ??
                                    (methods: const {}, grinders: const {}),
                                onShowMethodBrews: widget.onShowMethodBrews,
                                onBrewWithMethod: widget.onBrewWithMethod,
                                showArchived: showArchived,
                                onEditMethod: _editMethod,
                                onArchiveMethod: _archiveMethod,
                                onEditGrinder: _editGrinder,
                                onArchiveGrinder: _archiveGrinder,
                                onManageTools: (method) => showMethodTools(
                                  context,
                                  widget.repository,
                                  method,
                                ),
                              ),
                      );
                    },
                  ),
            ),
          },
        ),
      ],
    );
  }
}

class _EquipmentSectionList extends StatelessWidget {
  const _EquipmentSectionList({
    required this.repository,
    required this.section,
    required this.methods,
    required this.grinders,
    required this.usage,
    required this.showArchived,
    required this.onShowMethodBrews,
    required this.onBrewWithMethod,
    required this.onEditMethod,
    required this.onArchiveMethod,
    required this.onEditGrinder,
    required this.onArchiveGrinder,
    required this.onManageTools,
  });

  final JournalRepository repository;
  final EquipmentSection section;
  final List<BrewMethod> methods;
  final List<Grinder> grinders;
  final EquipmentOverview usage;
  final bool showArchived;
  final ValueChanged<BrewMethod>? onShowMethodBrews;
  final ValueChanged<BrewMethod>? onBrewWithMethod;
  final ValueChanged<BrewMethod> onEditMethod;
  final ValueChanged<BrewMethod> onArchiveMethod;
  final ValueChanged<Grinder> onEditGrinder;
  final ValueChanged<Grinder> onArchiveGrinder;
  final ValueChanged<BrewMethod> onManageTools;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    if (section == EquipmentSection.methods) {
      // The methods in use first, by their last brew; unused ones after,
      // by name.
      final lastUse = {
        for (final entry in usage.methods.entries)
          entry.key: entry.value.lastMs ?? -1,
      };
      final visible =
          methods
              .where(
                (method) =>
                    method.templateType != 'cupping' &&
                    (showArchived || method.archivedAtMs == null),
              )
              .toList()
            ..sort((a, b) {
              final byUse = (lastUse[b.id] ?? -1).compareTo(
                lastUse[a.id] ?? -1,
              );
              return byUse != 0
                  ? byUse
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
        itemCount: visible.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) return CuppingEntry(repository: repository);
          final method = visible[index - 1];
          return _MethodCard(
            method: method,
            use:
                usage.methods[method.id] ??
                (count: 0, rating: null, lastMs: null),
            onEdit: () => onEditMethod(method),
            onPiston:
                method.machine == 'meticulous' && method.machineAddress != null
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PistonPage(
                        repository: repository.piston,
                        methodId: method.id,
                        address: method.machineAddress!,
                        name: method.name,
                      ),
                    ),
                  )
                : null,
            onManageTools: () => onManageTools(method),
            onArchive: () => onArchiveMethod(method),
            onDelete: () => deleteEquipmentAfterConfirming(
              context,
              name: method.name,
              check: () => repository.methodDeletionBlockers(method.id),
              delete: () => repository.deleteUnusedMethod(method.id),
            ),
            onBrewWith: method.archivedAtMs == null && onBrewWithMethod != null
                ? () => onBrewWithMethod!(method)
                : null,
            onShowBrews: onShowMethodBrews == null
                ? null
                : () => onShowMethodBrews!(method),
          );
        },
      );
    }

    final visible = grinders
        .where((grinder) => showArchived || grinder.archivedAtMs == null)
        .toList();
    if (visible.isEmpty) return Center(child: Text(s.noGrinders));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
      itemCount: visible.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final grinder = visible[index];
        final use =
            usage.grinders[grinder.id] ??
            (
              brewCount: 0,
              lastBrewedAtMs: null,
              usualSettings: const <({String method, String setting})>[],
            );
        final details = <String>[
          if (use.brewCount > 0)
            [
              s.brewsCount(use.brewCount),
              if (use.lastBrewedAtMs case final last?)
                '${s.lastUsed} ${formatRegionalDate(DateTime.fromMillisecondsSinceEpoch(last), regionalLocale)}',
            ].join(', '),
          if (use.usualSettings.isNotEmpty)
            s.grinderUsualSettings(
              [
                for (final usual in use.usualSettings.take(3))
                  '${usual.method} ${usual.setting}',
              ].join(', '),
            ),
          if (grinder.notes?.isNotEmpty == true) grinder.notes!,
          if (grinder.archivedAtMs != null) s.archivedStatus,
        ];
        return Card(
          key: ValueKey('grinder-card-${grinder.id}'),
          child: ListTile(
            title: Text(
              grinder.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            // Whole: the usual setting per method is what it is read for.
            subtitle: details.isEmpty ? null : Text(details.join('\n')),
            onTap: () => onEditGrinder(grinder),
            trailing: PopupMenuButton<String>(
              tooltip: s.actions,
              onSelected: (value) => value == 'edit'
                  ? onEditGrinder(grinder)
                  : onArchiveGrinder(grinder),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(s.editGrinder)),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    grinder.archivedAtMs == null
                        ? s.archiveGrinder
                        : s.restoreGrinder,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A method with its style and jug, how much it is used and its rating,
/// its menu and the buttons to brew with it or see its brews.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.use,
    required this.onEdit,
    required this.onManageTools,
    this.onPiston,
    required this.onArchive,
    required this.onDelete,
    required this.onBrewWith,
    required this.onShowBrews,
  });

  final BrewMethod method;

  /// The method's brews.
  final MethodUse use;
  final VoidCallback onEdit;
  final VoidCallback onManageTools;
  final VoidCallback? onPiston;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onBrewWith;
  final VoidCallback? onShowBrews;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    final details = <String>[
      if (method.category != null) _styleLabel(s, method.category!),
      if (method.vesselGrams case final jug?)
        '${method.vesselName ?? s.methodJug} (${number.format(jug)} g)',
      if (method.archivedAtMs != null) s.archivedStatus,
    ];
    return Card(
      key: ValueKey('method-card-${method.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              method.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: details.isEmpty
                ? null
                : Text(
                    details.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: onEdit,
            trailing: PopupMenuButton<String>(
              tooltip: s.actions,
              onSelected: (value) => switch (value) {
                'edit' => onEdit(),
                'tools' => onManageTools(),
                'piston' => onPiston?.call(),
                'delete' => onDelete(),
                _ => onArchive(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(s.editMethod)),
                PopupMenuItem(value: 'tools', child: Text(s.manageMethodTools)),
                if (onPiston != null)
                  PopupMenuItem(value: 'piston', child: Text(s.pistonTitle)),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    method.archivedAtMs == null
                        ? s.archiveMethod
                        : s.restoreMethod,
                  ),
                ),
                PopupMenuItem(value: 'delete', child: Text(s.deleteMethod)),
              ],
            ),
          ),
          if (onPiston != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey('piston-method-${method.id}'),
                  onPressed: onPiston,
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: Text(s.pistonTitle),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              [
                s.brewsCount(use.count),
                if (use.rating case final average?)
                  '${s.averageRating} ${number.format(average)}',
                if (use.lastMs != null)
                  '${s.lastUsed} ${formatRegionalDate(DateTime.fromMillisecondsSinceEpoch(use.lastMs!), regionalLocale)}',
              ].join(', '),
              key: ValueKey('method-stats-${method.id}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                if (onBrewWith case final onBrewWith?)
                  TextButton.icon(
                    key: ValueKey('brew-with-method-${method.id}'),
                    onPressed: onBrewWith,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                    ),
                    icon: const Icon(Icons.coffee_maker_outlined),
                    label: Text(s.actionBrew),
                  ),
                if (onShowBrews case final onShowBrews? when use.count > 0)
                  TextButton.icon(
                    key: ValueKey('method-brews-${method.id}'),
                    onPressed: onShowBrews,
                    icon: const Icon(Icons.history_rounded),
                    label: Text(s.seeMethodBrews),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _styleLabel(AppLocalizations strings, String code) =>
    switch (MethodCategory.fromCode(code, allowLegacy: true)) {
      MethodCategory.espresso => strings.styleEspresso,
      // Percolation is no longer offered: methods that kept it read as pour
      // overs, which is how they brew.
      MethodCategory.pourover => strings.stylePourover,
      MethodCategory.immersion => strings.styleImmersion,
      null => code,
    };
