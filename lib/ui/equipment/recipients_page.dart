import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/equipment_overview.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// "Kinto SCS-S02 (179.3 g)": the vessel and its empty weight.
String recipientLabel(Recipient row, AppLocalizations s) =>
    '${row.name} (${NumberFormat('0.#', regionalLocale.toString()).format(row.emptyGrams)} g)';

Future<Recipient?> showRecipientForm(
  BuildContext context,
  JournalRepository repository, [
  Recipient? existing,
]) => showFormSheet(
  context,
  _RecipientForm(repository: repository, existing: existing),
);

class _RecipientForm extends StatefulWidget {
  const _RecipientForm({required this.repository, this.existing});
  final JournalRepository repository;
  final Recipient? existing;
  @override
  State<_RecipientForm> createState() => _RecipientFormState();
}

class _RecipientFormState extends State<_RecipientForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name);
  late final grams = TextEditingController(
    text: fieldExact(widget.existing?.emptyGrams),
  );
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    grams.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final row = await widget.repository.saveRecipient(
        id: widget.existing?.id,
        name: name.text,
        emptyGrams: parseNumber(grams.text)!,
      );
      if (mounted) Navigator.pop(context, row);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(
          context,
          error,
          AppLocalizations.of(context)!.saveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SheetFrame(
      title: widget.existing == null ? s.addRecipient : s.editRecipient,
      formKey: form,
      saving: saving,
      onSave: save,
      children: [
        TextFormField(
          key: const ValueKey('recipient-name'),
          controller: name,
          maxLength: 120,
          decoration: InputDecoration(labelText: s.jugName),
          validator: (v) =>
              v == null || v.trim().isEmpty ? s.requiredField : null,
        ),
        TextFormField(
          key: const ValueKey('recipient-grams'),
          controller: grams,
          inputFormatters: [decimalInputFormatter],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: s.jugEmptyWeight),
          validator: (v) {
            final n = parseNumber(v ?? '');
            return n == null || !n.isFinite || n <= 0 || n > 10000
                ? s.invalidNumber
                : null;
          },
        ),
      ],
    );
  }
}

class RecipientsList extends StatefulWidget {
  const RecipientsList({
    super.key,
    required this.repository,
    required this.showArchived,
  });
  final JournalRepository repository;
  final bool showArchived;
  @override
  State<RecipientsList> createState() => _RecipientsListState();
}

class _RecipientsListState extends State<RecipientsList> {
  late final rows = widget.repository.watchRecipients(includeArchived: true);
  late final brews = widget.repository.reads.watchRecipientUses();
  Future<void> archive(Recipient row) async {
    try {
      await widget.repository.setRecipientArchived(
        row.id,
        archived: row.archivedAtMs == null,
      );
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
    return StreamBuilder<List<Recipient>>(
      stream: rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(s.saveFailed));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final visible = snapshot.data!
            .where((r) => widget.showArchived || r.archivedAtMs == null)
            .toList();
        if (visible.isEmpty) return Center(child: Text(s.recipientsEmpty));
        // Cards like the other equipment: name, empty weight and use, with
        // the actions in a menu.
        return StreamBuilder<Map<String, int>>(
          stream: brews,
          builder: (context, brewSnapshot) {
            if (brewSnapshot.hasError) return Center(child: Text(s.dataError));
            final uses = brewSnapshot.data ?? const <String, int>{};
            final grams = NumberFormat('0.#', regionalLocale.toString());
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = visible[index];
                return Card(
                  key: ValueKey('vessel-card-${row.id}'),
                  child: ListTile(
                    title: Text(
                      row.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        s.vesselEmptyWeight(
                          '${grams.format(row.emptyGrams)} g',
                        ),
                        s.brewsCount(uses[row.id] ?? 0),
                        if (row.archivedAtMs != null) s.archivedStatus,
                      ].join('\n'),
                    ),
                    onTap: () =>
                        showRecipientForm(context, widget.repository, row),
                    trailing: PopupMenuButton<String>(
                      tooltip: s.actions,
                      onSelected: (value) => value == 'edit'
                          ? showRecipientForm(context, widget.repository, row)
                          : archive(row),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(s.editRecipient),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(
                            row.archivedAtMs == null
                                ? s.archiveRecipient
                                : s.restore,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class RecipientPicker extends StatefulWidget {
  const RecipientPicker({
    super.key,
    required this.repository,
    required this.value,
    required this.onChanged,
    this.snapshot,
    this.isDefault = false,
  });
  final JournalRepository repository;
  final String? value;
  final Recipient? snapshot;
  final ValueChanged<Recipient?> onChanged;
  final bool isDefault;
  @override
  State<RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<RecipientPicker> {
  late final rows = widget.repository.watchRecipients(includeArchived: true);
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return StreamBuilder<List<Recipient>>(
      stream: rows,
      builder: (context, snapshot) {
        final options = [
          for (final r in snapshot.data ?? <Recipient>[])
            if (r.archivedAtMs == null || r.id == widget.value) r,
        ];
        if (widget.snapshot case final saved?) {
          options.removeWhere((r) => r.id == saved.id);
          options.add(saved);
        }
        final value = options.any((r) => r.id == widget.value)
            ? widget.value
            : '';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'recipient-picker:$value:${widget.snapshot?.emptyGrams}',
                ),
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.isDefault
                      ? s.defaultRecipient
                      : s.recipient,
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(s.noRecipient)),
                  for (final row in options)
                    DropdownMenuItem(
                      value: row.id,
                      child: Text(
                        recipientLabel(row, s),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: snapshot.hasData
                    ? (id) => widget.onChanged(
                        options.where((r) => r.id == id).firstOrNull,
                      )
                    : null,
              ),
            ),
            IconButton(
              tooltip: s.addRecipient,
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () async {
                final row = await showRecipientForm(context, widget.repository);
                if (row != null && mounted) widget.onChanged(row);
              },
            ),
          ],
        );
      },
    );
  }
}
