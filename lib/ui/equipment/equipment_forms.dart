import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/domain/journal_codes.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/gaggimate_shot_widgets.dart'
    show gaggimateError;
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';

/// Opens the form to add a brew method, or edit [existing]. Returns the
/// saved method, or null when cancelled.
Future<BrewMethod?> showMethodForm(
  BuildContext context,
  JournalRepository repository, [
  BrewMethod? existing,
]) => showFormSheet(
  context,
  _MethodForm(repository: repository, existing: existing),
);

/// Opens the form to add a grinder, or edit [existing]. Returns the saved
/// grinder, or null when cancelled.
Future<Grinder?> showGrinderForm(
  BuildContext context,
  JournalRepository repository, [
  Grinder? existing,
]) => showFormSheet(
  context,
  _GrinderForm(repository: repository, existing: existing),
);

class _MethodForm extends StatefulWidget {
  const _MethodForm({required this.repository, this.existing});

  final JournalRepository repository;
  final BrewMethod? existing;

  @override
  State<_MethodForm> createState() => _MethodFormState();
}

class _MethodFormState extends State<_MethodForm> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name);
  late final notes = TextEditingController(text: widget.existing?.notes);
  late final address = TextEditingController(
    text: widget.existing?.machineAddress,
  );
  String? category;
  late String? machine = widget.existing?.machine;
  late String? recipientId = widget.existing?.defaultRecipientId;
  bool saving = false;

  /// Result of the last connection test: null while untested.
  ({bool ok, String text})? connection;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    // "Percolation" was offered until October 2026; it brews like a pour
    // over, so editing such a method shows and saves it as one.
    category =
        MethodCategory.fromCode(
          widget.existing?.category,
          allowLegacy: true,
        )?.code ??
        widget.existing?.category;
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    address.dispose();

    super.dispose();
  }

  /// Reads the latest shot from the machine, without changing anything.
  Future<void> testConnection() async {
    if (testing) return;
    final s = AppLocalizations.of(context);
    final testedMachine = machine;
    final testedAddress = address.text;
    GaggimateSource? gaggimate;
    MeticulousSource? meticulous;
    setState(() {
      testing = true;
      connection = null;
    });
    try {
      String? profile;
      if (testedMachine == 'gaggimate') {
        gaggimate = connectGaggimate(testedAddress);
        profile = (await gaggimate.history()).firstOrNull?.profileName;
      } else {
        meticulous = connectMeticulous(testedAddress);
        profile = (await meticulous.recentShots(limit: 1))
            .firstOrNull
            ?.profileName;
      }
      if (!mounted ||
          machine != testedMachine ||
          address.text != testedAddress) {
        return;
      }
      setState(
        () => connection = (
          ok: true,
          text: profile == null
              ? s.machineConnectedEmpty
              : s.machineConnected(profile),
        ),
      );
    } on GaggimateException catch (error) {
      if (mounted &&
          machine == testedMachine &&
          address.text == testedAddress) {
        setState(
          () =>
              connection = (ok: false, text: gaggimateError(s, error.failure)),
        );
      }
    } on FormatException {
      if (!mounted) return;
      setState(
        () => connection = (ok: false, text: s.meticulousInvalidAddress),
      );
    } on MeticulousException catch (error) {
      if (mounted) {
        setState(
          () => connection = (
            ok: false,
            text: s.meticulousConnectFailed(error.message),
          ),
        );
      }
    } finally {
      meticulous?.close();
      gaggimate?.close();
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final existing = widget.existing;
      final id = existing == null
          ? await widget.repository.createMethod(
              name: name.text,
              category: category,
              notes: notes.text,
              machine: machine,
              machineAddress: machine == null ? null : address.text,
              defaultRecipientId: recipientId,
              useRecipientCatalog: true,
            )
          : existing.id;
      if (existing != null) {
        await widget.repository.updateMethod(
          id: id,
          name: name.text,
          category: category,
          templateType: existing.templateType,
          notes: notes.text,
          machine: machine,
          machineAddress: machine == null ? null : address.text,
          defaultRecipientId: recipientId,
          useRecipientCatalog: true,
        );
      }
      if (mounted) {
        Navigator.pop(
          context,
          BrewMethod(
            id: id,
            name: name.text.trim(),
            category: category,
            templateType: existing?.templateType,
            notes: _trimOrNull(notes.text),
            machine: machine,
            machineAddress: machine == null ? null : _trimOrNull(address.text),
            defaultRecipientId: recipientId,
            archivedAtMs: existing?.archivedAtMs,
          ),
        );
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
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Where the machine is and whether it answers.
  List<Widget> _machineFields(AppLocalizations s) => [
    // Room between the dropdown's helper and the floating label.
    const SizedBox(height: 4),
    TextFormField(
      key: const ValueKey('method-machine-address'),
      controller: address,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: s.meticulousAddress,
        hintText: machine == 'gaggimate'
            ? s.gaggimateAddressHint
            : s.meticulousAddressHint,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        try {
          if (machine == 'gaggimate') {
            GaggimateClient.normalizeAddress(value);
          } else {
            MeticulousClient.normalizeAddress(value);
          }
          return null;
        } on FormatException {
          return s.meticulousInvalidAddress;
        }
      },
      onChanged: (_) => setState(() => connection = null),
    ),
    Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('method-machine-test'),
          onPressed: testing || address.text.trim().isEmpty
              ? null
              : testConnection,
          icon: testing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_find_rounded),
          label: Text(s.testConnection),
        ),
        if (connection case final result?)
          Text(
            result.text,
            key: const ValueKey('method-machine-status'),
            style: TextStyle(
              color: result.ok
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    ),
  ];

  List<Widget> _recipientFields(AppLocalizations s) => [
    RecipientPicker(
      repository: widget.repository,
      value: recipientId,
      isDefault: true,
      isPortafilter:
          MethodCategory.fromCode(category) == MethodCategory.espresso,
      onChanged: (row) => setState(() => recipientId = row?.id),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return _CatalogFormFrame(
      title: widget.existing == null ? s.addMethod : s.editMethod,
      formKey: formKey,
      saving: saving,
      onSave: save,
      children: [
        TextFormField(
          controller: name,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: s.methodName, counterText: ''),
          validator: (value) =>
              value == null || value.trim().isEmpty ? s.requiredField : null,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(category),
          initialValue: category,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.methodStyle),
          hint: Text(s.none),
          items: [
            DropdownMenuItem(value: '', child: Text(s.none)),
            DropdownMenuItem(
              value: MethodCategory.espresso.code,
              child: Text(s.styleEspresso),
            ),
            DropdownMenuItem(
              value: MethodCategory.pourover.code,
              child: Text(s.stylePourover),
            ),
            DropdownMenuItem(
              value: MethodCategory.immersion.code,
              child: Text(s.styleImmersion),
            ),
          ],
          onChanged: (value) => setState(() {
            final next = value == null || value.isEmpty ? null : value;
            if ((MethodCategory.fromCode(next) == MethodCategory.espresso) !=
                (MethodCategory.fromCode(category) ==
                    MethodCategory.espresso)) {
              recipientId = null;
            }
            category = next;
          }),
          validator: (value) =>
              widget.existing == null && (value == null || value.isEmpty)
              ? s.requiredField
              : null,
        ),
        DropdownButtonFormField<String>(
          key: const ValueKey('method-machine'),
          initialValue: machine ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: s.connectedMachine,
            helperText: s.connectedMachineHint,
            helperMaxLines: 3,
          ),
          items: [
            DropdownMenuItem(value: '', child: Text(s.none)),
            const DropdownMenuItem(
              value: 'meticulous',
              child: Text('Meticulous'),
            ),
            DropdownMenuItem(value: 'gaggimate', child: Text(s.gaggimateName)),
          ],
          onChanged: (value) => setState(() {
            machine = value == null || value.isEmpty ? null : value;
            connection = null;
            // A Meticulous is an espresso machine.
            if (machine != null && category == null) {
              category = MethodCategory.espresso.code;
              recipientId = null;
            }
          }),
        ),
        if (machine != null) ..._machineFields(s),
        ..._recipientFields(s),
        TextFormField(
          controller: notes,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: InputDecoration(labelText: s.methodNotes),
        ),
      ],
    );
  }
}

class _GrinderForm extends StatefulWidget {
  const _GrinderForm({required this.repository, this.existing});

  final JournalRepository repository;
  final Grinder? existing;

  @override
  State<_GrinderForm> createState() => _GrinderFormState();
}

class _GrinderFormState extends State<_GrinderForm> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name);
  late final notes = TextEditingController(text: widget.existing?.notes);
  late bool hasAdjustableRpm = widget.existing?.hasAdjustableRpm ?? false;
  late bool hasAdjustableFeederRpm =
      widget.existing?.hasAdjustableFeederRpm ?? false;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final existing = widget.existing;
      final id = existing == null
          ? await widget.repository.createGrinder(
              name: name.text,
              notes: notes.text,
              hasAdjustableRpm: hasAdjustableRpm,
              hasAdjustableFeederRpm: hasAdjustableFeederRpm,
            )
          : existing.id;
      if (existing != null) {
        await widget.repository.updateGrinder(
          id: id,
          name: name.text,
          notes: notes.text,
          hasAdjustableRpm: hasAdjustableRpm,
          hasAdjustableFeederRpm: hasAdjustableFeederRpm,
        );
      }
      if (mounted) {
        Navigator.pop(
          context,
          Grinder(
            id: id,
            name: name.text.trim(),
            notes: _trimOrNull(notes.text),
            hasAdjustableRpm: hasAdjustableRpm,
            hasAdjustableFeederRpm: hasAdjustableFeederRpm,
            archivedAtMs: existing?.archivedAtMs,
          ),
        );
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
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return _CatalogFormFrame(
      title: widget.existing == null ? s.addGrinder : s.editGrinder,
      formKey: formKey,
      saving: saving,
      onSave: save,
      children: [
        TextFormField(
          controller: name,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: s.grinderName,
            counterText: '',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? s.requiredField : null,
        ),
        TextFormField(
          controller: notes,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          decoration: InputDecoration(labelText: s.grinderNotes),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('grinder-adjustable-rpm'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.adjustableRpm),
          subtitle: Text(s.adjustableRpmHint),
          value: hasAdjustableRpm,
          onChanged: (value) => setState(() => hasAdjustableRpm = value),
        ),
        Semantics(
          label: s.adjustableFeederRpm,
          hint: s.adjustableFeederRpmHint,
          toggled: hasAdjustableFeederRpm,
          excludeSemantics: true,
          onTap: () =>
              setState(() => hasAdjustableFeederRpm = !hasAdjustableFeederRpm),
          child: SwitchListTile.adaptive(
            key: const ValueKey('grinder-feeder-rpm'),
            contentPadding: EdgeInsets.zero,
            title: Text(s.adjustableFeederRpm),
            subtitle: Text(s.adjustableFeederRpmHint),
            value: hasAdjustableFeederRpm,
            onChanged: (value) =>
                setState(() => hasAdjustableFeederRpm = value),
          ),
        ),
      ],
    );
  }
}

String? _trimOrNull(String value) {
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

class _CatalogFormFrame extends StatelessWidget {
  const _CatalogFormFrame({
    required this.title,
    required this.formKey,
    required this.saving,
    required this.onSave,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height - keyboard;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: available * .88,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              Expanded(
                child: Form(
                  key: formKey,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    itemCount: children.length,
                    itemBuilder: (context, index) => children[index],
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
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
                        onPressed: saving ? null : onSave,
                        child: Text(s.save),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
