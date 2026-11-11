import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/domain/freeze_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freeze_portions_fields.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/core/semantic_colors.dart';
import 'package:intl/intl.dart';

String frozenContainerLabel(AppLocalizations s, String? code) => switch (code) {
  'vacuum_bag' => s.containerVacuumBag,
  'tube' => s.containerTube,
  'zip_bag' => s.containerZipBag,
  'jar' => s.containerJar,
  'container' => s.containerBox,
  'original_bag' => s.containerOriginalBag,
  'other' => s.containerOther,
  _ => '',
};

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

double? _parseGrams(String text) {
  final value = parseNumber(text);
  return value == null || !value.isFinite ? null : value;
}

/// Opens the freeze form for new portions, or the edit form when [existing]
/// is given. Returns the saved portions' labels.
Future<List<String>?> showFreezeSheet(
  BuildContext context,
  JournalRepository repository, {
  required List<CoffeeLot> lots,
  FrozenPortion? existing,
}) => showFormSheet(
  context,
  _FreezeForm(repository: repository, lots: lots, existing: existing),
  useSafeArea: true,
);

class _FreezeForm extends StatefulWidget {
  const _FreezeForm({
    required this.repository,
    required this.lots,
    this.existing,
  });

  final JournalRepository repository;
  final List<CoffeeLot> lots;
  final FrozenPortion? existing;

  @override
  State<_FreezeForm> createState() => _FreezeFormState();
}

class _FreezeFormState extends State<_FreezeForm> {
  final formKey = GlobalKey<FormState>();
  late String? lotId =
      widget.existing?.lotId ??
      widget.lots.where((lot) => (unfrozenGrams(lot) ?? 0) > 0).firstOrNull?.id;
  late final grams = TextEditingController(
    text: widget.existing == null
        ? ''
        : fieldNumber(widget.existing!.initialGrams),
  );
  late final notes = TextEditingController(text: widget.existing?.notes);
  late String? container = widget.existing?.container;
  late DateTime frozenDate =
      DateTime.tryParse(widget.existing?.frozenDate ?? '') ?? DateTime.now();
  bool saving = false;
  bool split = false;
  bool includeRemainder = true;
  final portionGrams = TextEditingController(text: '100');

  @override
  void initState() {
    super.initState();
    grams.addListener(_refreshPlan);
    portionGrams.addListener(_refreshPlan);
  }

  void _refreshPlan() => setState(() {});

  FreezePlan? get plan {
    try {
      return FreezePlan(
        totalGrams: _parseGrams(grams.text) ?? 0,
        portionGrams: _parseGrams(portionGrams.text) ?? 0,
      );
    } on ArgumentError {
      return null;
    }
  }

  CoffeeLot? get lot => widget.lots.where((row) => row.id == lotId).firstOrNull;

  /// Most grams this portion may hold: the lot's unfrozen balance, plus what
  /// the portion already holds when editing.
  double? get maximumGrams {
    final selected = lot;
    if (selected == null) return null;
    final fresh = unfrozenGrams(selected);
    if (fresh == null) return null;
    final existing = widget.existing;
    return existing == null ? fresh : fresh + existing.initialGrams;
  }

  @override
  void dispose() {
    grams.removeListener(_refreshPlan);
    portionGrams.dispose();
    grams.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      locale: regionalLocale,
      initialDate: frozenDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => frozenDate = selected);
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate() || lotId == null) return;
    final s = AppLocalizations.of(context)!;
    setState(() => saving = true);
    try {
      final value = _parseGrams(grams.text)!;
      final existing = widget.existing;
      if (existing == null) {
        final ids = await widget.repository.freezeCoffeePortions(
          lotId: lotId!,
          amounts: split
              ? plan!.amounts(includeRemainder: includeRemainder)
              : [value],
          frozenDate: _isoDate(frozenDate),
          container: container,
          notes: notes.text,
        );
        final saved = (await widget.repository.frozenPortionsForLot(lotId!))
            .where((portion) => ids.contains(portion.id));
        if (mounted) Navigator.pop(context, saved.map((p) => p.label).toList());
      } else {
        await widget.repository.updateFrozenPortion(
          id: existing.id,
          initialGrams: value,
          frozenDate: _isoDate(frozenDate),
          container: container,
          notes: notes.text,
        );
        if (mounted) Navigator.pop(context, [existing.label]);
      }
    } catch (error, stack) {
      reportError(error, stack);
      if (!mounted) return;
      setState(() => saving = false);
      showOperationError(context, error, s.saveFailed);
    }
  }

  /// Which bag to freeze from, when the coffee has more than one; bags
  /// with nothing left to freeze cannot be chosen.
  Widget _lotField(AppLocalizations s) => DropdownButtonFormField<String>(
    initialValue: lotId,
    isExpanded: true,
    decoration: InputDecoration(labelText: s.inventoryLot),
    items: [
      for (var index = 0; index < widget.lots.length; index++)
        DropdownMenuItem(
          value: widget.lots[index].id,
          enabled: (unfrozenGrams(widget.lots[index]) ?? 0) > 0,
          child: Text(
            [
              s.inventoryItem(index + 1),
              if (unfrozenGrams(widget.lots[index]) case final g?)
                formatGrams(g, regionalLocale.toString()),
            ].join(', '),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (value) => setState(() => lotId = value),
  );

  /// Grams to freeze: no more than is fresh and, when editing, no less than
  /// has been thawed already.
  Widget _gramsField(AppLocalizations s) {
    final maximum = maximumGrams;
    final existing = widget.existing;
    final thawedGrams = existing == null
        ? 0.0
        : existing.initialGrams - existing.remainingGrams;
    return TextFormField(
      key: const ValueKey('freeze-grams'),
      controller: grams,
      inputFormatters: [decimalInputFormatter],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '${s.freezeAmount} (g)',
        helperText: maximum == null
            ? null
            : '${s.availableFresh}: ${formatGrams(existing == null ? maximum : maximum - existing.initialGrams, regionalLocale.toString())}',
      ),
      validator: (value) {
        final parsed = _parseGrams(value ?? '');
        if (parsed == null || parsed <= 0) return s.invalidNumber;
        if (maximum == null || parsed > maximum + 1e-6) {
          return s.notEnoughToFreeze;
        }
        if (parsed < thawedGrams - 1e-6) return s.invalidNumber;
        return null;
      },
    );
  }

  /// Usual amounts that fit in [maximum], and all of it.
  Widget _presets(AppLocalizations s, double maximum) {
    final presets = [
      15.0,
      18.0,
      20.0,
      100.0,
    ].where((preset) => preset <= maximum).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final preset in presets)
          ActionChip(
            label: Text(formatGrams(preset, regionalLocale.toString())),
            onPressed: () => grams.text = fieldNumber(preset, decimals: 1),
          ),
        ActionChip(
          key: const ValueKey('freeze-all'),
          label: Text(s.allAmount),
          onPressed: () => grams.text = fieldNumber(maximum),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final maximum = maximumGrams;
    final existing = widget.existing;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              existing == null ? s.freezeCoffee : s.editFrozenPortion,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (existing != null) ...[
              const SizedBox(height: 4),
              Text('${s.portionLabel}: ${existing.label}'),
            ],
            const SizedBox(height: 20),
            if (existing == null && widget.lots.length > 1) ...[
              _lotField(s),
              const SizedBox(height: 20),
            ],
            _gramsField(s),
            if (existing == null && maximum != null && maximum > 0) ...[
              const SizedBox(height: 8),
              _presets(s, maximum),
            ],
            if (existing == null)
              FreezePortionsFields(
                split: split,
                portionGrams: portionGrams,
                plan: plan,
                includeRemainder: includeRemainder,
                onSplit: (value) => setState(() => split = value),
                onRemainder: (value) =>
                    setState(() => includeRemainder = value),
              ),
            const SizedBox(height: 20),
            Text(s.container, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final code in JournalRepository.frozenContainers)
                  ChoiceChip(
                    label: Text(frozenContainerLabel(s, code)),
                    selected: container == code,
                    onSelected: (selected) =>
                        setState(() => container = selected ? code : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                key: const ValueKey('freeze-date'),
                tooltip: s.frozenDate,
                avatar: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  '${s.frozenDate}: ${formatRegionalDate(frozenDate, regionalLocale)}',
                ),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notes,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(labelText: s.notes),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('freeze-save'),
                    onPressed: saving || lotId == null ? null : _save,
                    child: Text(s.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks how many grams of [portion] to thaw, with [note] above when given.
/// Returns null when cancelled.
Future<double?> showThawDialog(
  BuildContext context,
  FrozenPortion portion, {
  String? note,
}) => showDialog<double>(
  context: context,
  builder: (_) => _ThawDialog(portion: portion, note: note),
);

class _ThawDialog extends StatefulWidget {
  const _ThawDialog({required this.portion, this.note});

  final FrozenPortion portion;

  /// Why the dialog is asking, when it comes from somewhere else.
  final String? note;

  @override
  State<_ThawDialog> createState() => _ThawDialogState();
}

class _ThawDialogState extends State<_ThawDialog> {
  final formKey = GlobalKey<FormState>();
  late final grams = TextEditingController(
    text: fieldNumber(widget.portion.remainingGrams),
  );

  @override
  void dispose() {
    grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final remaining = widget.portion.remainingGrams;
    return AlertDialog(
      key: const ValueKey('thaw-dialog'),
      title: Text('${s.thaw} ${widget.portion.label}'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.note case final note?)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(note, key: const ValueKey('thaw-note')),
              ),
            TextFormField(
              key: const ValueKey('thaw-grams'),
              controller: grams,
              autofocus: true,
              inputFormatters: [decimalInputFormatter],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '${s.thawAmount} (g)',
                helperText:
                    '${s.frozen}: ${formatGrams(remaining, regionalLocale.toString())}',
              ),
              validator: (value) {
                final parsed = _parseGrams(value ?? '');
                if (parsed == null || parsed <= 0) return s.invalidNumber;
                if (parsed > remaining + 1e-6) return s.thawTooMuch;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          key: const ValueKey('thaw-confirm'),
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, _parseGrams(grams.text));
          },
          child: Text(s.thaw),
        ),
      ],
    );
  }
}

/// One frozen portion inside a bean's detail sheet.
class FrozenPortionCard extends StatelessWidget {
  const FrozenPortionCard({
    super.key,
    required this.portion,
    required this.onThaw,
    required this.onThawAndBrew,
    required this.onEdit,
    required this.onDelete,
    this.roastDate,
  });

  final FrozenPortion portion;
  final VoidCallback? onThaw;
  final VoidCallback? onThawAndBrew;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Roast date of the portion's lot, used to show how old the coffee was
  /// when freezing paused its ageing.
  final DateTime? roastDate;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final thawed = portion.remainingGrams <= 0;
    final partial = !thawed && portion.remainingGrams < portion.initialGrams;
    final status = thawed
        ? s.thawed
        : partial
        ? s.frozenPartial
        : s.frozen;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final frozenDate = DateTime.tryParse(portion.frozenDate);
    final details = [
      if (frozenDate != null)
        s.frozenOn(formatRegionalDate(frozenDate, regionalLocale)),
      if (portion.container != null) frozenContainerLabel(s, portion.container),
    ].join(', ');
    final ageWhenFrozen = frozenAtRoastAge(portion, roastDate);
    return Card(
      key: ValueKey('frozen-portion-${portion.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: thawed ? colors.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    thawed ? Icons.water_drop_outlined : Icons.ac_unit_rounded,
                    size: 20,
                    color: thawed
                        ? colors.onSurfaceVariant
                        : frozenColor(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          portion.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '${number.format(portion.remainingGrams)} / ${formatGrams(portion.initialGrams, regionalLocale.toString())}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: s.actions,
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(s.editFrozenPortion),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(s.deleteFrozenPortion),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, right: 10),
              child: Text(
                details,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            if (ageWhenFrozen != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, right: 10, top: 2),
                child: Text(
                  s.frozenAtAge(ageWhenFrozen),
                  key: ValueKey('frozen-age-${portion.id}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (portion.notes != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, right: 10, top: 2),
                child: Text(portion.notes!),
              ),
            if (!thawed)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                // Thawing to brew is what a portion is usually taken out
                // for: it leads, and thawing alone sits beside it.
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      key: ValueKey('thaw-brew-${portion.id}'),
                      onPressed: onThawAndBrew,
                      icon: const Icon(Icons.coffee_maker_outlined),
                      label: Text(s.thawAndBrew),
                    ),
                    OutlinedButton.icon(
                      key: ValueKey('thaw-${portion.id}'),
                      onPressed: onThaw,
                      icon: const Icon(Icons.thermostat_rounded),
                      label: Text(s.thaw),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
