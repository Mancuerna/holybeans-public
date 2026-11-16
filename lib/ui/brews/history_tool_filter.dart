import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_tools.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/l10n/app_localizations.dart';

class HistoryToolFilter extends StatelessWidget {
  const HistoryToolFilter({
    super.key,
    required this.tools,
    required this.selected,
    required this.onChanged,
  });

  final List<MethodTool> tools;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return InkWell(
      key: const ValueKey('history-tool-filter'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => _ToolSelectionSheet(
          tools: tools,
          selected: selected,
          onChanged: onChanged,
        ),
      ),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: s.methodTools,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          selected.isEmpty
              ? s.historyAnyAccessory
              : s.historySelectedAccessories(selected.length),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ToolSelectionSheet extends StatefulWidget {
  const _ToolSelectionSheet({
    required this.tools,
    required this.selected,
    required this.onChanged,
  });

  final List<MethodTool> tools;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ToolSelectionSheet> createState() => _ToolSelectionSheetState();
}

class _ToolSelectionSheetState extends State<_ToolSelectionSheet> {
  late final selected = widget.selected.toSet();
  String query = '';

  void change(VoidCallback update) {
    setState(update);
    widget.onChanged(List.unmodifiable(selected));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final needle = foldSuggestion(query);
    final tools = HistoryTools(widget.tools);
    final matches = tools.options
        .where((tool) => foldSuggestion(tool.name).contains(needle))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                s.methodTools,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(s.historyAccessoriesHint),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('history-tool-search'),
                decoration: InputDecoration(
                  labelText: s.search,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            ListTile(
              key: const ValueKey('history-any-tool'),
              title: Text(s.historyAnyAccessory),
              selected: selected.isEmpty,
              onTap: () => change(selected.clear),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(s.historyNoMatchingAccessories),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final tool = matches[index];
                        final aliases = tools.groups([tool.id]).single;
                        return CheckboxListTile(
                          key: ValueKey('history-tool-choice-${tool.id}'),
                          title: Text(tool.name),
                          subtitle: tool.archivedAtMs == null
                              ? null
                              : Text(s.archived),
                          value: selected.any(aliases.contains),
                          onChanged: (value) => change(() {
                            if (value == true) {
                              selected.add(tool.id);
                            } else {
                              selected.removeWhere(aliases.contains);
                            }
                          }),
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
