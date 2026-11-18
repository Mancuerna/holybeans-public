import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/equipment_presets.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/equipment_delete.dart';

class EquipmentPresetList extends StatefulWidget {
  const EquipmentPresetList({super.key, required this.repository, this.onBrew});
  final JournalRepository repository;
  final ValueChanged<PresetDetails>? onBrew;
  @override
  State<EquipmentPresetList> createState() => _EquipmentPresetListState();
}

class _EquipmentPresetListState extends State<EquipmentPresetList> {
  late final presets = widget.repository.presets.watch();
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return StreamBuilder<List<PresetDetails>>(
      stream: presets,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(s.dataError));
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(s.equipmentPresetsEmpty),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final details = rows[index];
            final p = details.preset;
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: Text(p.name),
                    subtitle: Text(
                      [
                        details.parts.join(' · '),
                        s.brewsCount(details.uses),
                        if (!details.available) s.equipmentPresetUnavailable,
                      ].join('\n'),
                    ),
                    trailing: details.uses != 0
                        ? null
                        : IconButton(
                            tooltip: s.delete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteEquipmentAfterConfirming(
                              context,
                              name: p.name,
                              check: () =>
                                  widget.repository.presets.blockers(p.id),
                              delete: () =>
                                  widget.repository.presets.delete(p.id),
                            ),
                          ),
                  ),
                  if (details.available && widget.onBrew != null)
                    TextButton.icon(
                      onPressed: () => widget.onBrew!(details),
                      icon: const Icon(Icons.coffee_outlined),
                      label: Text(s.actionBrew),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

typedef _Options = Map<String, String>;
typedef _Catalog = ({
  _Options methods,
  _Options grinders,
  _Options waters,
  ToolCatalog tools,
});

Future<void> showEquipmentPresetForm(
  BuildContext context,
  JournalRepository repository,
) async {
  await showFormSheet<bool>(
    context,
    _PresetForm(repository),
    useSafeArea: true,
  );
}

class _PresetForm extends StatefulWidget {
  const _PresetForm(this.repository);
  final JournalRepository repository;
  @override
  State<_PresetForm> createState() => _PresetFormState();
}

class _PresetFormState extends State<_PresetForm> {
  final key = GlobalKey<FormState>();
  String name = '';
  String? method;
  String? grinder;
  String? water;
  final tools = <String>{};
  bool saving = false;
  late final catalog = _load();

  Future<_Catalog> _load() async {
    final r = widget.repository;
    final (methods, grinders, waters, tools) = await (
      r.records.activeMethods(),
      r.records.activeGrinders(),
      r.records.activeWaterProfiles(),
      r.toolCatalog(),
    ).wait;
    return (
      methods: {for (final m in methods) m.id: m.name},
      grinders: {for (final g in grinders) g.id: g.name},
      waters: {for (final w in waters) w.id: w.name},
      tools: tools,
    );
  }

  Future<void> _save() async {
    if (saving || !key.currentState!.validate() || method == null) return;
    setState(() => saving = true);
    try {
      await widget.repository.presets.create(
        name: name,
        methodId: method!,
        grinderId: grinder,
        waterProfileId: water,
        toolIds: tools,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() => saving = false);
        showOperationError(
          context,
          error,
          AppLocalizations.of(context).saveFailed,
        );
      }
    }
  }

  Widget _field(
    String label,
    String? id,
    _Options values,
    ValueChanged<String?> change, {
    bool optional = false,
  }) {
    final s = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      initialValue: id ?? (optional ? '' : null),
      items: [
        if (optional) DropdownMenuItem(value: '', child: Text(s.none)),
        for (final e in values.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      validator: (v) => !optional && v == null ? s.requiredField : null,
      onChanged: saving
          ? null
          : (v) => setState(() => change(v == '' ? null : v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return FutureBuilder<_Catalog>(
      future: catalog,
      builder: (context, snap) {
        final c = snap.data;
        return SheetFrame(
          title: s.createEquipmentPreset,
          formKey: key,
          saving: saving || c == null || c.methods.isEmpty,
          onSave: _save,
          children: [
            if (snap.hasError)
              Text(s.dataError)
            else if (c == null)
              const LinearProgressIndicator()
            else if (c.methods.isEmpty)
              Text(s.noActiveMethods)
            else ...[
              TextFormField(
                decoration: InputDecoration(labelText: s.equipmentPresetName),
                maxLength: 120,
                onChanged: (v) => name = v,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? s.requiredField : null,
              ),
              _field(s.method, method, c.methods, (id) {
                method = id;
                tools.clear();
              }),
              _field(
                s.grinder,
                grinder,
                c.grinders,
                (id) => grinder = id,
                optional: true,
              ),
              if (method case final id?)
                for (final tool in c.tools.forMethod(id))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tool.name),
                    value: tools.contains(tool.id),
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              tools.add(tool.id);
                            } else {
                              tools.remove(tool.id);
                            }
                          }),
                  ),
              _field(
                s.waterTab,
                water,
                c.waters,
                (id) => water = id,
                optional: true,
              ),
            ],
          ],
        );
      },
    );
  }
}
