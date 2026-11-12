import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/profiles/profile_editor_model.dart';
import 'package:holybeans/ui/profiles/profile_plot.dart';

class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key,
    required this.profile,
    required this.onSave,
  });
  final ExtractionProfile profile;
  final Future<void> Function(ExtractionProfile) onSave;
  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final model = ProfileEditorModel(widget.profile)
    ..active = widget.profile.primary;
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.profile.name);
  late final dose = TextEditingController(text: '${widget.profile.doseGrams}');
  late final temperature = TextEditingController(
    text: '${widget.profile.temperatureC}',
  );
  late final target = TextEditingController(
    text:
        '${widget.profile.targetGrams ?? widget.profile.predictedGrams ?? 36}',
  );
  late final notes = TextEditingController(text: widget.profile.notes);
  bool saving = false;
  bool saved = false;
  bool metadataDirty = false;
  double? number(String? text) =>
      double.tryParse((text ?? '').replaceAll(',', '.'));
  @override
  void dispose() {
    model.dispose();
    for (final c in [name, dose, temperature, target, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final profile = model.profile.copyWith(
        name: name.text.trim(),
        doseGrams: number(dose.text),
        temperatureC: number(temperature.text),
        targetGrams: number(target.text),
        notes: notes.text,
      );
      await widget.onSave(profile);
      if (!mounted) return;
      setState(() {
        saved = true;
        saving = false;
      });
      Navigator.pop(context, profile);
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).profileError)),
        );
      }
    }
  }

  Future<void> editPoint(int i) async {
    final s = AppLocalizations.of(context);
    final p = model.points[i];
    final t = TextEditingController(text: '${p.elapsedMs / 1000}');
    final v = TextEditingController(text: '${p.value}');
    final key = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.profilePoint),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: t,
                decoration: InputDecoration(labelText: s.profileTime),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (text) {
                  final n = number(text);
                  if (n == null || !n.isFinite) return s.profileInvalid;
                  final ms = (n * 1000).round();
                  return ms < 0 ||
                          ms > model.profile.durationMs ||
                          i > 0 && ms <= model.points[i - 1].elapsedMs ||
                          i < model.points.length - 1 &&
                              ms >= model.points[i + 1].elapsedMs
                      ? s.profileInvalid
                      : null;
                },
              ),
              TextFormField(
                controller: v,
                decoration: InputDecoration(
                  labelText: model.active == 'flow' ? 'g/s' : 'bar',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (text) {
                  final n = number(text);
                  return n == null || !n.isFinite || n < 0 || n > 30
                      ? s.profileInvalid
                      : null;
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
            onPressed: () {
              if (!key.currentState!.validate()) return;
              model.move(i, (number(t.text)! * 1000).round(), number(v.text)!);
              Navigator.pop(context);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    // Dialog controllers outlive the route's exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    t.dispose();
    v.dispose();
  }

  Future<void> scaleDuration() async {
    final s = AppLocalizations.of(context);
    final c = TextEditingController(text: '${model.profile.durationMs / 1000}');
    final key = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.profileScaleDuration),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.profileScaleHelp),
              TextFormField(
                controller: c,
                decoration: InputDecoration(labelText: s.profileDuration),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (text) {
                  final n = number(text);
                  return n == null || !n.isFinite || n < 1 || n > 600
                      ? s.profileInvalid
                      : null;
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
            onPressed: () {
              if (!key.currentState!.validate()) return;
              try {
                model.scaleDuration((number(c.text)! * 1000).round());
                Navigator.pop(context);
              } on FormatException {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(s.profileInvalid)));
              }
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    c.dispose();
  }

  Future<void> leave() async {
    final s = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.profileDiscard),
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
    if (discard == true && mounted) {
      setState(() => saved = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Widget numeric(
    TextEditingController c,
    String label,
    double min,
    double max,
  ) {
    final s = AppLocalizations.of(context);
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final n = number(text);
        return n == null || !n.isFinite || n < min || n > max
            ? s.profileInvalid
            : null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => PopScope(
        canPop: saved || !saving && !model.dirty && !metadataDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !saving) leave();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(s.profileEditor)),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: saving ? null : save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? '…' : s.save),
              ),
            ),
          ),
          body: Form(
            key: form,
            onChanged: () {
              if (!metadataDirty) setState(() => metadataDirty = true);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: s.profileNameLabel),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? s.profileInvalid : null,
                ),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 140,
                      child: numeric(dose, s.profileDose, .1, 100),
                    ),
                    SizedBox(
                      width: 140,
                      child: numeric(temperature, s.profileTemperature, 0, 110),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(s.profileChannels),
                  subtitle: Text(
                    model.profile.flow.isNotEmpty &&
                            model.profile.pressure.isNotEmpty
                        ? s.profileBoth
                        : model.profile.flow.isNotEmpty
                        ? s.curveFlow
                        : s.curvePressure,
                  ),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final channel in ['flow', 'pressure'])
                          FilterChip(
                            label: Text(
                              channel == 'flow' ? s.curveFlow : s.curvePressure,
                            ),
                            selected:
                                (channel == 'flow'
                                        ? model.profile.flow
                                        : model.profile.pressure)
                                    .isNotEmpty,
                            onSelected: (selected) {
                              final channels = {
                                if (model.profile.flow.isNotEmpty) 'flow',
                                if (model.profile.pressure.isNotEmpty)
                                  'pressure',
                              };
                              selected
                                  ? channels.add(channel)
                                  : channels.remove(channel);
                              model.setChannels(channels);
                            },
                          ),
                      ],
                    ),
                    if (model.profile.flow.isNotEmpty &&
                        model.profile.pressure.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(model.profile.primary),
                        initialValue: model.profile.primary,
                        decoration: InputDecoration(
                          labelText: s.profilePrimary,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'flow',
                            child: Text(s.curveFlow),
                          ),
                          DropdownMenuItem(
                            value: 'pressure',
                            child: Text(s.curvePressure),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            model.change(model.profile.copyWith(primary: v));
                          }
                        },
                      ),
                    const SizedBox(height: 12),
                    Text(s.profileClock),
                    const SizedBox(height: 12),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final channel in ['flow', 'pressure'])
                      if ((channel == 'flow'
                              ? model.profile.flow
                              : model.profile.pressure)
                          .isNotEmpty)
                        ChoiceChip(
                          label: Text(
                            channel == 'flow'
                                ? '${s.curveFlow} · g/s'
                                : '${s.curvePressure} · bar',
                          ),
                          selected: model.active == channel,
                          onSelected: (_) => model.select(channel),
                        ),
                  ],
                ),
                ProfilePlot(profile: model.profile, editor: model),
                Text(s.profileDrag),
                const SizedBox(height: 12),
                if (model.profile.predictedGrams case final grams?)
                  Text(
                    '${s.profilePredicted}: ${grams.toStringAsFixed(1)} g · 1:${(grams / ((number(dose.text) ?? 0) > 0 ? number(dose.text)! : model.profile.doseGrams)).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                else
                  Text(s.profileUnknownWeight),
                if (model.profile.flow.isEmpty ||
                    model.profile.predictedGrams == null)
                  numeric(target, s.profileTargetWeight, .1, 2000),
                TextButton.icon(
                  onPressed: scaleDuration,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    '${s.profileScaleDuration} · ${model.profile.durationMs / 1000} s',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: model.add,
                        icon: const Icon(Icons.add),
                        label: Text(s.profileAddPoint),
                      ),
                    ),
                    IconButton(
                      onPressed: model.canUndo ? model.undo : null,
                      tooltip: s.profileUndo,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      onPressed: model.canRedo ? model.redo : null,
                      tooltip: s.profileRedo,
                      icon: const Icon(Icons.redo),
                    ),
                  ],
                ),
                for (var i = 0; i < model.points.length; i++)
                  ListTile(
                    dense: true,
                    selected: model.selected == i,
                    leading: Text('${i + 1}'),
                    title: Text(
                      '${(model.points[i].elapsedMs / 1000).toStringAsFixed(2)} s     ${model.points[i].value.toStringAsFixed(2)} ${model.active == 'flow' ? 'g/s' : 'bar'}',
                    ),
                    onTap: () {
                      model.select(model.active, i);
                      editPoint(i);
                    },
                    trailing: IconButton(
                      tooltip: s.delete,
                      onPressed: i == 0 || i == model.points.length - 1
                          ? null
                          : () => model.remove(i),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                TextFormField(
                  controller: notes,
                  maxLength: 1200,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: s.profileNotes),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
