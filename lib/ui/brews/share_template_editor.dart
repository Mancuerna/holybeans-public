import 'package:flutter/material.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:holybeans/ui/core/brew_parameter_labels.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/share_markdown_text.dart';
import 'package:uuid/uuid.dart';

class ShareTemplateEditor extends StatefulWidget {
  const ShareTemplateEditor({
    super.key,
    required this.style,
    required this.onSave,
    this.existing,
    this.values,
    this.importing = false,
  });

  final bool importing;
  final ShareTemplateStyle style;
  final Future<void> Function(ShareTemplate) onSave;
  final ShareTemplate? existing;
  final Map<String, String>? values;

  @override
  State<ShareTemplateEditor> createState() => _ShareTemplateEditorState();
}

class _ShareTemplateEditorState extends State<ShareTemplateEditor> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  final body = TextEditingController();
  String? initialBody;
  bool saving = false;
  String? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialBody != null) return;
    final s = AppLocalizations.of(context)!;
    initialBody =
        widget.existing?.body ??
        (widget.style == ShareTemplateStyle.espresso
            ? s.shareTemplateExampleEspresso
            : s.shareTemplateExampleFilter);
    body.text = initialBody!;
  }

  @override
  void dispose() {
    name.dispose();
    body.dispose();
    super.dispose();
  }

  void _insert(String tag) {
    final selection = body.selection;
    final start = selection.isValid ? selection.start : body.text.length;
    final end = selection.isValid ? selection.end : start;
    final token = '<$tag>';
    body.value = TextEditingValue(
      text: body.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _save(BuildContext context) async {
    final s = AppLocalizations.of(context)!;
    if (saving || !formKey.currentState!.validate()) return;
    final template = ShareTemplate(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      style: widget.style,
      body: body.text,
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(template);
      if (context.mounted) FormExitGuard.complete(context, template);
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          saving = false;
          error = s.shareTemplateFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final values = widget.values ?? sampleShareTemplateValues(s, widget.style);
    final unknown = TemplateEngine.unknownTags(body.text);
    final missing = TemplateEngine.missingTags(body.text, values);
    return FormExitGuard(
      hasChanges: () =>
          name.text != (widget.existing?.name ?? '') ||
          body.text != initialBody,
      busy: () => saving,
      child: Builder(
        builder: (context) => SheetFrame(
          title: widget.importing
              ? s.shareTemplateImportReview
              : widget.existing == null
              ? s.shareTemplateNew
              : s.shareTemplateEdit,
          formKey: formKey,
          writesJournal: false,
          saving: saving,
          showScrollCue: true,
          onSave: () => _save(context),
          children: [
            if (widget.importing) Text(s.shareTemplateImportHint),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              widget.style == ShareTemplateStyle.espresso
                  ? s.styleEspresso
                  : s.styleFilter,
            ),
            TextFormField(
              key: const ValueKey('template-name'),
              controller: name,
              enabled: !saving,
              maxLength: 80,
              decoration: InputDecoration(labelText: s.shareTemplateName),
              validator: (value) => value == null || value.trim().isEmpty
                  ? s.shareTemplateInvalid
                  : null,
            ),
            TextFormField(
              key: const ValueKey('template-body'),
              controller: body,
              enabled: !saving,
              minLines: 4,
              maxLines: 10,
              maxLength: 8000,
              decoration: InputDecoration(labelText: s.shareTemplateBody),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      TemplateEngine.unknownTags(value).isNotEmpty
                  ? s.shareTemplateInvalid
                  : null,
            ),
            // Right under the text, so it shows while typing.
            Card(
              key: const ValueKey('template-preview-card'),
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.values == null
                          ? s.shareTemplateSample
                          : s.shareTemplatePreview,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    shareMarkdownText(
                      TemplateEngine.renderMarkdown(body.text, values),
                      selectable: true,
                      key: const ValueKey('template-preview'),
                    ),
                    if (missing.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        (widget.values == null
                            ? s.shareTemplateSampleMissing
                            : s.shareTemplateMissing)(
                          missing.map((t) => '<$t>').join(', '),
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Text(s.shareTemplateHelp),
            if (unknown.isNotEmpty)
              Text(
                s.shareTemplateUnknown(unknown.map((t) => '<$t>').join(', ')),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ExpansionTile(
              key: const ValueKey('template-tags'),
              title: Text(s.shareTemplateTags),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in shareTemplateTags.entries)
                      ActionChip(
                        key: ValueKey('template-tag-${entry.key}'),
                        tooltip: entry.key == 'country_flag'
                            ? s.shareTemplateCountryFlag
                            : entry.value.label(s),
                        label: Text('<${entry.key}>'),
                        onPressed: saving ? null : () => _insert(entry.key),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
