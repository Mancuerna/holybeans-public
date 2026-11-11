import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_exit_guard.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/labels/label_editor.dart';
import 'package:holybeans/ui/labels/label_graphic_controller.dart';
import 'package:holybeans/ui/labels/label_output_settings.dart';
import 'package:holybeans/ui/labels/label_printer_controls.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:holybeans/ui/labels/label_values.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class LabelPrintPage extends StatefulWidget {
  const LabelPrintPage({
    super.key,
    required this.coffee,
    required this.components,
    required this.lots,
    required this.portions,
    required this.templates,
    required this.settings,
    required this.printer,
    this.otherPrinters = const [],
    this.outputPreferences,
  });
  final Coffee coffee;
  final List<CoffeeComponent> components;
  final List<CoffeeLot> lots;
  final List<FrozenPortion> portions;
  final List<LabelTemplate> templates;
  final ShareTemplateSettings settings;
  final LabelPrinter printer;
  final List<LabelPrinter> otherPrinters;
  final LabelOutputPreferences? outputPreferences;

  @override
  State<LabelPrintPage> createState() => _LabelPrintPageState();
}

class _LabelPrintPageState extends State<LabelPrintPage> {
  final body = TextEditingController();
  late List<LabelTemplate> templates = [...widget.templates];
  LabelKind kind = LabelKind.coffee;
  late LabelPrinter printer = widget.printer;
  late LabelPaper paper = printer.model.defaultPaper;
  final graphic = LabelGraphicController();
  String? cleanGraphic;
  LabelImageOptions imageOptions = const LabelImageOptions();
  LabelImageOptions cleanImageOptions = const LabelImageOptions();
  LabelLayout? _cachedLayout;
  bool get dirty =>
      body.text != cleanBody ||
      graphic.data != cleanGraphic ||
      imageOptions != cleanImageOptions;
  CoffeeLot? lot;
  FrozenPortion? portion;
  String? selectedTemplate;
  String? cleanBody;
  String? feedback;
  bool error = false;
  bool busy = false;
  bool upsideDown = false;
  int copies = 1;
  final kindField = GlobalKey<FormFieldState<LabelKind>>();
  final templateField = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    graphic.addListener(_graphicChanged);
    final preferences = widget.outputPreferences;
    printer = [widget.printer, ...widget.otherPrinters].firstWhere(
      (candidate) => candidate.model == preferences?.model,
      orElse: () => widget.printer,
    );
    paper = preferences?.paperFor(printer.model) ?? printer.model.defaultPaper;
    final active = widget.lots.where((l) => l.archivedAtMs == null).toList();
    lot = active.length == 1
        ? active.single
        : widget.lots.length == 1
        ? widget.lots.single
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (cleanBody == null) _resetBody();
  }

  void _graphicChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _changePrinter(LabelPrinter next) async {
    if (busy || next == printer) return;
    setState(() => busy = true);
    try {
      await printer.stopSearch();
      await printer.disconnect();
      if (!mounted) return;
      setState(() {
        printer = next;
        paper =
            widget.outputPreferences?.paperFor(next.model) ??
            next.model.defaultPaper;
        feedback = null;
      });
      await _rememberOutput();
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          feedback = AppLocalizations.of(context).labelConnectionFailed;
          error = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _rememberOutput() async {
    try {
      await widget.outputPreferences?.remember(paper);
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          feedback = AppLocalizations.of(context).labelOutputSaveFailed;
          error = true;
        });
      }
    }
  }

  Future<void> _changePaper(LabelPaper value) async {
    if (busy || paper == value) return;
    setState(() {
      paper = value;
      busy = true;
      feedback = null;
    });
    await _rememberOutput();
    if (mounted) setState(() => busy = false);
  }

  void _resetBody() {
    final s = AppLocalizations.of(context);
    body.text = kind == LabelKind.coffee
        ? s.labelCoffeeBody
        : s.labelFrozenBody;
    cleanBody = body.text;
    selectedTemplate = null;
    cleanGraphic = null;
    imageOptions = cleanImageOptions = const LabelImageOptions();
    graphic.load(null);
  }

  @override
  void dispose() {
    body.dispose();
    graphic.dispose();
    super.dispose();
  }

  LabelTemplate get template => LabelTemplate(
    id: selectedTemplate ?? 'draft',
    name: 'draft',
    kind: kind,
    body: body.text,
    imagePng: graphic.data,
    imageOptions: imageOptions,
  );
  Map<String, String> get values => coffeeLabelValues(
    coffee: widget.coffee,
    components: widget.components,
    lot: lot,
    portion: portion,
  );

  void _insert(String tag) {
    final selection = body.selection;
    final start = selection.isValid ? selection.start : body.text.length;
    final end = selection.isValid ? selection.end : start;
    final token = '<$tag>';
    setState(
      () => body.value = TextEditingValue(
        text: body.text.replaceRange(start, end, token),
        selection: TextSelection.collapsed(offset: start + token.length),
      ),
    );
  }

  Future<bool> _allowReplace() async {
    if (!dirty) return true;
    final s = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.discardChangesTitle),
        content: Text(s.discardChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.discardChanges),
          ),
        ],
      ),
    );
    return mounted && discard == true;
  }

  Future<void> _changeKind(LabelKind? value) async {
    if (value == null || value == kind) return;
    final replace = await _allowReplace();
    if (!mounted) return;
    setState(() {
      if (replace) {
        kind = value;
        portion = null;
        final active = widget.lots
            .where((l) => l.archivedAtMs == null)
            .toList();
        lot = active.length == 1
            ? active.single
            : widget.lots.length == 1
            ? widget.lots.single
            : null;
        _resetBody();
        templateField.currentState?.didChange('');
      }
      kindField.currentState?.didChange(kind);
    });
  }

  Future<void> _changeTemplate(String? id) async {
    if (id == null || id == (selectedTemplate ?? '')) return;
    final replace = await _allowReplace();
    if (!mounted) return;
    setState(() {
      if (replace) {
        if (id.isEmpty) {
          _resetBody();
        } else {
          selectedTemplate = id;
          final chosen = templates.firstWhere((t) => t.id == id);
          body.text = chosen.body;
          cleanGraphic = chosen.imagePng;
          imageOptions = cleanImageOptions = chosen.effectiveImageOptions;
          graphic.load(chosen.imagePng);
          cleanBody = body.text;
        }
      }
      templateField.currentState?.didChange(selectedTemplate ?? '');
    });
  }

  Future<void> _save() async {
    if (busy) return;
    final s = AppLocalizations.of(context);
    final previous = templates
        .where((t) => t.id == selectedTemplate)
        .firstOrNull;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => LabelTemplateNameDialog(initial: previous?.name ?? ''),
    );
    if (name == null || !mounted) return;
    final saved = LabelTemplate(
      id: previous?.id ?? const Uuid().v4(),
      name: name,
      kind: kind,
      body: body.text,
      imagePng: graphic.data,
      imageOptions: imageOptions,
    );
    setState(() => busy = true);
    try {
      await widget.settings.saveLabelTemplate(saved);
      if (!mounted) return;
      setState(() {
        templates = [...templates.where((t) => t.id != saved.id), saved];
        selectedTemplate = saved.id;
        templateField.currentState?.didChange(saved.id);
        cleanBody = saved.body;
        cleanGraphic = saved.imagePng;
        cleanImageOptions = saved.effectiveImageOptions;
        feedback = s.labelTemplateSaved;
        error = false;
      });
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          feedback = s.labelSaveFailed;
          error = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    if (busy || selectedTemplate == null) return;
    final s = AppLocalizations.of(context);
    final id = selectedTemplate!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.labelTemplateDelete),
        content: Text(templates.firstWhere((t) => t.id == id).name),
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
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.settings.deleteLabelTemplate(id);
      if (mounted) {
        setState(() {
          templates.removeWhere((t) => t.id == id);
          _resetBody();
          templateField.currentState?.didChange('');
          feedback = null;
        });
      }
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          feedback = s.labelSaveFailed;
          error = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _output(LabelLayout layout, {required bool print}) async {
    if (busy || !layout.fitsPaper) return;
    final s = AppLocalizations.of(context);
    setState(() {
      busy = true;
      feedback = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final bitmap = await layout.rasterize(upsideDown: upsideDown);
      if (!mounted) return;
      if (print) {
        await printer.printLabel(bitmap.pixels, paper, copies: copies);
        if (mounted) {
          setState(() {
            feedback = s.labelPrinted;
            error = false;
          });
        }
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bitmap.png, mimeType: 'image/png')],
            fileNameOverrides: ['holybeans-label.png'],
          ),
        );
      }
    } catch (problem, stack) {
      reportError(problem, stack);
      if (mounted) {
        setState(() {
          feedback = print ? s.labelPrintFailed : s.labelExportFailed;
          error = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final current = template;
    final unknown = TemplateEngine.unknownTags(
      body.text,
      allowedTags: current.allowedTags,
    );
    final missing = TemplateEngine.missingTags(
      body.text,
      values,
      allowedTags: current.allowedTags,
    );
    final rendered = current.render(values);
    final cached = _cachedLayout;
    final layout =
        cached != null &&
            cached.markdown == rendered &&
            cached.paper == paper &&
            identical(cached.graphic, graphic.image) &&
            cached.imageOptions == imageOptions
        ? cached
        : (_cachedLayout = LabelLayout(
            rendered,
            paper,
            graphic: graphic.image,
            imageOptions: imageOptions,
          ));
    final sourceReady = kind == LabelKind.frozen
        ? portion != null
        : widget.lots.isEmpty || lot != null;
    final valid =
        sourceReady &&
        unknown.isEmpty &&
        (body.text.trim().isNotEmpty || graphic.image != null) &&
        !graphic.loading &&
        !graphic.failed &&
        body.text.length <= 8000 &&
        layout.fitsPaper;
    return FormExitGuard(
      hasChanges: () => dirty,
      busy: () => busy || graphic.loading,
      child: Scaffold(
        appBar: AppBar(title: Text(s.labelTitle)),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: busy || graphic.loading,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.coffee.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _sourceFields(s),
                const SizedBox(height: 16),
                LabelOutputSettings(
                  printers: [widget.printer, ...widget.otherPrinters],
                  printer: printer,
                  paper: paper,
                  onPrinter: _changePrinter,
                  onPaper: _changePaper,
                ),
                const SizedBox(height: 16),
                _templateFields(s, unknown, layout),
                if (!layout.fitsPaper) _warning(s.labelOverflow),
                if (missing.isNotEmpty)
                  _warning(s.shareTemplateMissing(missing.join(', '))),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.labelRotate),
                  value: upsideDown,
                  onChanged: (value) => setState(() => upsideDown = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: copies,
                  decoration: InputDecoration(labelText: s.labelCopies),
                  items: [
                    for (var n = 1; n <= 10; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => copies = value);
                  },
                ),
                const SizedBox(height: 16),
                LabelPrinterControls(printer: printer),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: printer,
                  builder: (context, _) => FilledButton.icon(
                    key: const ValueKey('label-print'),
                    onPressed: valid && !busy && printer.connected
                        ? () => _output(layout, print: true)
                        : null,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(
                      busy && printer.printing ? s.labelPrinting : s.labelPrint,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('label-export'),
                  onPressed: valid && !busy
                      ? () => _output(layout, print: false)
                      : null,
                  icon: const Icon(Icons.ios_share),
                  label: Text(s.labelExport),
                ),
                if (busy) const LinearProgressIndicator(),
                if (feedback case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      message,
                      key: const ValueKey('label-feedback'),
                      style: TextStyle(
                        color: error
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _warning(String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  String _sourceDate(String? value, String fallback) {
    final date = DateTime.tryParse(value ?? '');
    return date == null
        ? value ?? fallback
        : formatRegionalDate(date, regionalLocale);
  }

  Widget _sourceFields(AppLocalizations s) => Column(
    children: [
      DropdownButtonFormField<LabelKind>(
        key: kindField,
        isExpanded: true,
        initialValue: kind,
        decoration: InputDecoration(labelText: s.labelKind),
        items: [
          DropdownMenuItem(value: LabelKind.coffee, child: Text(s.labelCoffee)),
          DropdownMenuItem(
            value: LabelKind.frozen,
            child: Text(
              s.labelFrozen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        onChanged: _changeKind,
      ),
      const SizedBox(height: 12),
      if (kind == LabelKind.coffee && widget.lots.length > 1)
        DropdownButtonFormField<String>(
          key: ValueKey('label-lot-${kind.name}'),
          initialValue: lot?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: s.labelLot,
            helperText: lot == null ? s.labelChooseLot : null,
          ),
          items: [
            for (final (index, item) in widget.lots.indexed)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  '${index + 1} · ${_sourceDate(item.roastDate, s.labelNoDate)}',
                ),
              ),
          ],
          onChanged: (id) =>
              setState(() => lot = widget.lots.firstWhere((l) => l.id == id)),
        ),
      if (kind == LabelKind.frozen && widget.portions.isEmpty)
        Text(s.labelNoPortions),
      if (kind == LabelKind.frozen && widget.portions.isNotEmpty)
        DropdownButtonFormField<String>(
          key: const ValueKey('label-portion'),
          initialValue: portion?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: s.labelFrozen,
            helperText: s.labelChoosePortion,
          ),
          items: [
            for (final item in widget.portions)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  '${item.label} · ${_sourceDate(item.frozenDate, s.labelNoDate)}',
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            portion = widget.portions.firstWhere((p) => p.id == id);
            lot = widget.lots.firstWhere((l) => l.id == portion!.lotId);
          }),
        ),
    ],
  );

  Widget _templateFields(
    AppLocalizations s,
    Set<String> unknown,
    LabelLayout layout,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: templateField,
        initialValue: selectedTemplate ?? '',
        isExpanded: true,
        decoration: InputDecoration(labelText: s.labelTemplate),
        items: [
          DropdownMenuItem(value: '', child: Text(s.labelDefault)),
          for (final t in templates.where((t) => t.kind == kind))
            DropdownMenuItem(value: t.id, child: Text(t.name)),
        ],
        onChanged: _changeTemplate,
      ),
      const SizedBox(height: 12),
      LabelEditor(
        controller: body,
        layout: layout,
        unknown: unknown,
        upsideDown: upsideDown,
        keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
        onChanged: (_) => setState(() {
          feedback = null;
        }),
      ),
      const SizedBox(height: 12),
      LabelGraphicControls(
        graphic: graphic,
        options: imageOptions,
        onOptions: (value) => setState(() {
          imageOptions = value;
          feedback = null;
        }),
      ),
      ExpansionTile(
        title: Text(s.shareFields),
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final entry in labelTagNames(s, kind).entries)
                ActionChip(
                  label: Text(entry.value),
                  tooltip: '<${entry.key}>',
                  onPressed: () => _insert(entry.key),
                ),
            ],
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            key: const ValueKey('label-template-save'),
            onPressed:
                unknown.isEmpty &&
                    !graphic.loading &&
                    !graphic.failed &&
                    (body.text.trim().isNotEmpty || graphic.image != null)
                ? _save
                : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(s.labelTemplateSave),
          ),
          if (selectedTemplate != null)
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(s.labelTemplateDelete),
            ),
        ],
      ),
    ],
  );
}
