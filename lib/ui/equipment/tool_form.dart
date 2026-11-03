import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/domain/tool_catalog.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

Future<String?> showToolForm(
  BuildContext context,
  JournalRepository repository, {
  MethodTool? existing,
  String? initialMethodId,
}) => showFormSheet<String>(
  context,
  _ToolForm(
    repository: repository,
    existing: existing,
    initialMethodId: initialMethodId,
  ),
  useSafeArea: true,
);

class _ToolForm extends StatefulWidget {
  const _ToolForm({
    required this.repository,
    this.existing,
    this.initialMethodId,
  });
  final JournalRepository repository;
  final MethodTool? existing;
  final String? initialMethodId;

  @override
  State<_ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends State<_ToolForm> {
  final formKey = GlobalKey<FormState>();
  final focus = FocusNode();
  late final name = TextEditingController(text: widget.existing?.name);
  final selectedMethods = <String>{};
  ToolCatalog? catalog;
  List<BrewMethod> methods = const [];
  MethodTool? reused;
  bool failed = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.repository.toolCatalog();
      final rows = await widget.repository.allMethods();
      if (!mounted) return;
      setState(() {
        catalog = loaded;
        methods = rows;
        selectedMethods.addAll(loaded.methodsByTool[widget.existing?.id] ?? {});
        if (widget.initialMethodId case final id?) selectedMethods.add(id);
      });
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    name.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final existing = widget.existing ?? reused;
      final id =
          existing?.id ??
          await widget.repository.createTool(
            name: name.text,
            methodIds: selectedMethods.toList(),
          );
      if (existing != null) {
        await widget.repository.updateTool(
          id: id,
          name: name.text,
          methodIds: selectedMethods.toList(),
        );
      }
      if (mounted) Navigator.pop(context, id);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() => saving = false);
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    }
  }

  String _methodNames(MethodTool tool) => [
    for (final method in methods)
      if (catalog!.methodsByTool[tool.id]?.contains(method.id) ?? false)
        method.name,
  ].join(', ');

  Widget _nameField(AppLocalizations s) {
    Widget field(TextEditingController controller, FocusNode? node) =>
        TextFormField(
          key: const ValueKey('tool-name'),
          controller: controller,
          focusNode: node,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: s.toolName, counterText: ''),
          validator: (value) =>
              value == null || value.trim().isEmpty ? s.requiredField : null,
          onChanged: (_) {
            if (reused != null) setState(() => reused = null);
          },
        );
    if (widget.existing != null) return field(name, focus);
    return RawAutocomplete<MethodTool>(
      textEditingController: name,
      focusNode: focus,
      displayStringForOption: (tool) => tool.name,
      optionsBuilder: (value) {
        final query = foldSuggestion(value.text);
        if (query.isEmpty) return const [];
        return catalog!
            .visible()
            .where((tool) => foldSuggestion(tool.name).contains(query))
            .take(8);
      },
      onSelected: (tool) => setState(() {
        reused = tool;
        selectedMethods
          ..clear()
          ..addAll(catalog!.methodsByTool[tool.id] ?? {});
        if (widget.initialMethodId case final id?) selectedMethods.add(id);
        focus.unfocus();
      }),
      fieldViewBuilder: (context, controller, node, submit) =>
          field(controller, node),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width - 40,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final tool in options)
                    ListTile(
                      key: ValueKey('tool-suggestion-${tool.id}'),
                      title: Text(tool.name),
                      subtitle: Text(
                        [
                          _methodNames(tool),
                          s.brewsCount(catalog!.useCounts[tool.id] ?? 0),
                        ].where((text) => text.isNotEmpty).join(', '),
                      ),
                      onTap: () => select(tool),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SheetFrame(
      title: widget.existing == null ? s.addTool : s.editTool,
      formKey: formKey,
      saving: saving || catalog == null,
      onSave: _save,
      showScrollCue: true,
      children: [
        if (failed)
          Text(s.dataError)
        else if (catalog == null)
          const LinearProgressIndicator()
        else ...[
          _nameField(s),
          if (widget.existing == null)
            Text(reused == null ? s.reuseToolHint : s.toolReusedHint),
          Text(
            s.toolCompatibleMethods,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(s.toolCompatibleMethodsHint),
          for (final method in methods)
            if (method.archivedAtMs == null ||
                selectedMethods.contains(method.id))
              CheckboxListTile(
                key: ValueKey('tool-method-${method.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(method.name),
                subtitle: method.archivedAtMs == null
                    ? null
                    : Text(s.archivedStatus),
                value: selectedMethods.contains(method.id),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selectedMethods.add(method.id);
                        } else {
                          selectedMethods.remove(method.id);
                        }
                      }),
              ),
        ],
      ],
    );
  }
}
