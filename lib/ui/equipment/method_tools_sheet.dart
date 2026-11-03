import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/tool_catalog.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/tool_form.dart';

Future<void> showMethodTools(
  BuildContext context,
  JournalRepository repository,
  BrewMethod method,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) =>
      _MethodToolsSheet(repository: repository, method: method),
);

class _MethodToolsSheet extends StatefulWidget {
  const _MethodToolsSheet({required this.repository, required this.method});
  final JournalRepository repository;
  final BrewMethod method;
  @override
  State<_MethodToolsSheet> createState() => _MethodToolsSheetState();
}

class _MethodToolsSheetState extends State<_MethodToolsSheet> {
  late final catalog = widget.repository.watchToolCatalog();
  bool showArchived = true;

  Future<void> _add() async {
    final saved = await showToolForm(
      context,
      widget.repository,
      initialMethodId: widget.method.id,
    );
    if (saved != null && mounted) {
      showMessage(context, AppLocalizations.of(context)!.toolSaved);
    }
  }

  Future<void> _edit(MethodTool tool) async {
    final saved = await showToolForm(
      context,
      widget.repository,
      existing: tool,
    );
    if (saved != null && mounted) {
      showMessage(context, AppLocalizations.of(context)!.toolSaved);
    }
  }

  Future<void> _action(MethodTool tool, String action) async {
    try {
      if (action == 'detach') {
        await widget.repository.dissociateTool(tool.id, widget.method.id);
      } else {
        await widget.repository.setMethodToolArchived(
          tool.id,
          archived: tool.archivedAtMs == null,
        );
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.methodTools}: ${widget.method.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: s.addTool,
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                  ),
                  IconButton(
                    tooltip: s.cancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            SwitchListTile.adaptive(
              title: Text(s.showArchivedEquipment),
              value: showArchived,
              onChanged: (value) => setState(() => showArchived = value),
            ),
            Expanded(
              child: StreamBuilder<ToolCatalog>(
                stream: catalog,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(s.dataError));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final loaded = snapshot.data!;
                  final tools = loaded.forMethod(
                    widget.method.id,
                    includeArchived: showArchived,
                  );
                  if (tools.isEmpty) {
                    return Center(child: Text(s.noMethodTools));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: tools.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final tool = tools[index];
                      return Card(
                        child: ListTile(
                          title: Text(tool.name),
                          subtitle: Text(
                            [
                              s.brewsCount(loaded.useCounts[tool.id] ?? 0),
                              if (tool.archivedAtMs != null) s.archivedStatus,
                            ].join(', '),
                          ),
                          onTap: () => _edit(tool),
                          trailing: PopupMenuButton<String>(
                            tooltip: s.actions,
                            onSelected: (value) => value == 'edit'
                                ? _edit(tool)
                                : _action(tool, value),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(s.editTool),
                              ),
                              PopupMenuItem(
                                value: 'detach',
                                child: Text(s.detachTool),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  tool.archivedAtMs == null
                                      ? s.archiveSharedTool
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
            ),
          ],
        ),
      ),
    );
  }
}
