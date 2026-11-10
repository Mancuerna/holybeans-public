import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/brews/share_template_exchange.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/share_markdown_text.dart';

class ShareTemplatesPage extends StatefulWidget {
  const ShareTemplatesPage({
    super.key,
    required this.settings,
    this.style,
    this.values,
  });

  final ShareTemplateSettings settings;
  final ShareTemplateStyle? style;
  final Map<String, String>? values;

  @override
  State<ShareTemplatesPage> createState() => _ShareTemplatesPageState();
}

class _ShareTemplatesPageState extends State<ShareTemplatesPage> {
  late ShareTemplateStyle style = widget.style ?? ShareTemplateStyle.espresso;
  ShareConfiguration? config;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final next = await widget.settings.load();
      if (mounted) {
        setState(() {
          config = next;
          error = null;
        });
      }
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(
          () => error = AppLocalizations.of(context)!.shareTemplateLoadFailed,
        );
      }
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await _load();
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(
          () => error = AppLocalizations.of(context)!.shareTemplateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit([ShareTemplate? template]) async {
    await showFormSheet<ShareTemplate>(
      context,
      ShareTemplateEditor(
        style: style,
        existing: template,
        values: style == widget.style ? widget.values : null,
        onSave: widget.settings.saveTemplate,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _delete(ShareTemplate template) async {
    final s = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.shareTemplateDelete),
        content: Text(s.shareTemplateDeleteHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(() => widget.settings.deleteTemplate(template.id));
    }
  }

  Future<void> _import() async {
    setState(() => busy = true);
    final imported = await importShareTemplate(context, widget.settings);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (imported != null) style = imported.style;
    });
    await _load();
  }

  Future<void> _export(ShareTemplate template) async {
    setState(() => busy = true);
    await exportShareTemplate(context, template);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final templates =
        config?.templates.where((t) => t.style == style).toList() ?? [];
    final selected = config?.selected(style)?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.shareTemplatesTitle),
        actions: [
          IconButton(
            key: const ValueKey('template-import'),
            tooltip: s.shareTemplateImport,
            icon: const Icon(Icons.file_open_outlined),
            onPressed: busy || config == null ? null : _import,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          SegmentedButton<ShareTemplateStyle>(
            key: const ValueKey('template-style'),
            segments: [
              ButtonSegment(
                value: ShareTemplateStyle.espresso,
                label: Text(s.styleEspresso),
              ),
              ButtonSegment(
                value: ShareTemplateStyle.filter,
                label: Text(s.styleFilter),
              ),
            ],
            selected: {style},
            onSelectionChanged: busy
                ? null
                : (value) => setState(() => style = value.single),
          ),
          const SizedBox(height: 16),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (config == null && error == null) const LinearProgressIndicator(),
          if (config != null) ...[
            ListTile(
              key: const ValueKey('template-default-fields'),
              title: Text(s.shareTemplateFields),
              subtitle: Text(s.shareTemplateDefaultHint),
              trailing: selected == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              selected: selected == null,
              onTap: busy
                  ? null
                  : () => _change(() => widget.settings.select(style, null)),
            ),
            if (templates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.shareTemplateEmpty),
              ),
            for (final template in templates)
              _TemplateCard(
                template: template,
                preview: TemplateEngine.renderMarkdown(
                  template.body,
                  (style == widget.style ? widget.values : null) ??
                      sampleShareTemplateValues(s, style),
                ),
                isDefault: selected == template.id,
                busy: busy,
                onDefault: (on) => _change(
                  () => widget.settings.select(style, on ? template.id : null),
                ),
                onExport: () => _export(template),
                onEdit: () => _edit(template),
                onDelete: () => _delete(template),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('template-add'),
        onPressed: busy || config == null ? null : _edit,
        icon: const Icon(Icons.add),
        label: Text(s.shareTemplateNew),
      ),
    );
  }
}

/// A saved template: how it reads filled in, what it says, whether it is the
/// default for its style, and how to share, edit or delete it.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.preview,
    required this.isDefault,
    required this.busy,
    required this.onDefault,
    required this.onExport,
    required this.onEdit,
    required this.onDelete,
  });

  final ShareTemplate template;

  /// The template filled in with the brew being shared, or a sample.
  final String preview;
  final bool isDefault;

  /// Whether something is running, which disables every action.
  final bool busy;
  final ValueChanged<bool> onDefault;
  final VoidCallback onExport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.name, style: Theme.of(context).textTheme.titleMedium),
            // How it reads once filled in, then what it says.
            shareMarkdownText(
              preview,
              key: ValueKey('template-preview-${template.id}'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              template.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile(
              key: ValueKey('template-default-${template.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.shareTemplateDefault),
              value: isDefault,
              onChanged: busy ? null : onDefault,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  key: ValueKey('template-menu-${template.id}'),
                  tooltip: s.actions,
                  enabled: !busy,
                  onSelected: (_) => onExport(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'share',
                      child: Text(s.shareTemplateExport),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: s.shareTemplateEdit,
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: s.delete,
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
