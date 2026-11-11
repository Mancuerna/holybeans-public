import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/tool_form.dart';

class ToolsList extends StatefulWidget {
  const ToolsList({
    super.key,
    required this.repository,
    required this.showArchived,
  });
  final JournalRepository repository;
  final bool showArchived;
  @override
  State<ToolsList> createState() => _ToolsListState();
}

class _ToolsListState extends State<ToolsList> {
  late final catalog = widget.repository.watchToolCatalog();
  late final methods = widget.repository.watchMethods(includeArchived: true);

  Future<void> _edit(MethodTool tool) async {
    final result = await showToolForm(
      context,
      widget.repository,
      existing: tool,
    );
    if (result != null && mounted) {
      showMessage(context, AppLocalizations.of(context).toolSaved);
    }
  }

  Future<void> _archive(MethodTool tool) async {
    try {
      await widget.repository.setMethodToolArchived(
        tool.id,
        archived: tool.archivedAtMs == null,
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context).saveFailed,
        );
      }
    }
  }

  Future<void> _merge(
    MethodTool tool,
    ToolCatalog loaded,
    List<BrewMethod> methods,
  ) async {
    final target = await showDialog<String>(
      context: context,
      builder: (_) =>
          _MergeDialog(source: tool, catalog: loaded, methods: methods),
    );
    if (target == null || !mounted) return;
    try {
      await widget.repository.mergeTools(sourceId: tool.id, targetId: target);
      if (mounted) {
        showMessage(context, AppLocalizations.of(context).toolsMerged);
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context).saveFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return StreamBuilder<ToolCatalog>(
      stream: catalog,
      builder: (context, snapshot) => StreamBuilder<List<BrewMethod>>(
        stream: methods,
        builder: (context, methodSnapshot) {
          if (snapshot.hasError || methodSnapshot.hasError) {
            return Center(child: Text(s.dataError));
          }
          if (!snapshot.hasData || !methodSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final loaded = snapshot.data!;
          final visible = loaded.visible(includeArchived: widget.showArchived);
          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.noTools, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final tool = visible[index];
              final linked = [
                for (final method in methodSnapshot.data!)
                  if (loaded.methodsByTool[tool.id]?.contains(method.id) ??
                      false)
                    method.name,
              ];
              return Card(
                key: ValueKey('tool-card-${tool.id}'),
                child: ListTile(
                  title: Text(
                    tool.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      s.brewsCount(loaded.useCounts[tool.id] ?? 0),
                      if (linked.isNotEmpty)
                        linked.join(', ')
                      else
                        s.toolNoMethods,
                      if (tool.archivedAtMs != null) s.archivedStatus,
                    ].join('\n'),
                  ),
                  onTap: () => _edit(tool),
                  trailing: PopupMenuButton<String>(
                    tooltip: s.actions,
                    onSelected: (value) => switch (value) {
                      'edit' => _edit(tool),
                      'merge' => _merge(tool, loaded, methodSnapshot.data!),
                      _ => _archive(tool),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(s.editTool)),
                      if (loaded.visible().any((other) => other.id != tool.id))
                        PopupMenuItem(
                          value: 'merge',
                          child: Text(s.mergeTools),
                        ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(
                          tool.archivedAtMs == null
                              ? s.archiveTool
                              : s.restoreTool,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.source,
    required this.catalog,
    required this.methods,
  });
  final MethodTool source;
  final ToolCatalog catalog;
  final List<BrewMethod> methods;
  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  final formKey = GlobalKey<FormState>();
  String? target;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.mergeTools),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.mergeToolsHint(widget.source.name)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: const ValueKey('merge-tool-target'),
                isExpanded: true,
                decoration: InputDecoration(labelText: s.mergeToolTarget),
                items: [
                  for (final tool in widget.catalog.visible())
                    if (tool.id != widget.source.id)
                      DropdownMenuItem(
                        value: tool.id,
                        child: Text(
                          [
                            tool.name,
                            for (final method in widget.methods)
                              if (widget.catalog.methodsByTool[tool.id]
                                      ?.contains(method.id) ??
                                  false)
                                method.name,
                          ].join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: (id) => target = id,
                validator: (value) => value == null ? s.requiredField : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, target);
            }
          },
          child: Text(s.mergeTools),
        ),
      ],
    );
  }
}
