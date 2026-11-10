import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

Future<WaterProfile?> showWaterProfileForm(
  BuildContext context,
  JournalRepository repository, {
  WaterProfile? existing,
  WaterProfile? initial,
}) => showFormSheet(
  context,
  _WaterProfileForm(
    repository: repository,
    existing: existing,
    initial: initial,
  ),
);

class _WaterProfileForm extends StatefulWidget {
  const _WaterProfileForm({
    required this.repository,
    this.existing,
    this.initial,
  });

  final JournalRepository repository;
  final WaterProfile? existing;
  final WaterProfile? initial;

  @override
  State<_WaterProfileForm> createState() => _WaterProfileFormState();
}

class _WaterProfileFormState extends State<_WaterProfileForm> {
  WaterProfile? get _seed => widget.existing ?? widget.initial;
  final formKey = GlobalKey<FormState>();
  static String _display(double? value) =>
      value == null ? '' : fieldNumber(value);

  late final name = TextEditingController(text: _seed?.name);
  late final gh = TextEditingController(text: _display(_seed?.ghPpmAsCaCO3));
  late final kh = TextEditingController(text: _display(_seed?.khPpmAsCaCO3));
  late final tds = TextEditingController(text: _display(_seed?.tdsPpm));
  late final ph = TextEditingController(text: _display(_seed?.ph));
  late final notes = TextEditingController(text: _seed?.notes);
  late final calcium = _mineral(_seed?.calciumPpm);
  late final magnesium = _mineral(_seed?.magnesiumPpm);
  late final sodium = _mineral(_seed?.sodiumPpm);
  late final potassium = _mineral(_seed?.potassiumPpm);
  late final chloride = _mineral(_seed?.chloridePpm);
  late final sulfate = _mineral(_seed?.sulfatePpm);
  late final bicarbonate = _mineral(_seed?.bicarbonatePpm);
  bool saving = false;

  static TextEditingController _mineral(double? ppm) =>
      TextEditingController(text: _display(ppm));

  WaterMinerals get _minerals => WaterMinerals(
    calcium: _read(calcium, _seed?.calciumPpm),
    magnesium: _read(magnesium, _seed?.magnesiumPpm),
    sodium: _read(sodium, _seed?.sodiumPpm),
    potassium: _read(potassium, _seed?.potassiumPpm),
    chloride: _read(chloride, _seed?.chloridePpm),
    sulfate: _read(sulfate, _seed?.sulfatePpm),
    bicarbonate: _read(bicarbonate, _seed?.bicarbonatePpm),
  );

  @override
  void dispose() {
    name.dispose();
    gh.dispose();
    kh.dispose();
    tds.dispose();
    ph.dispose();
    notes.dispose();
    for (final controller in [
      calcium,
      magnesium,
      sodium,
      potassium,
      chloride,
      sulfate,
      bicarbonate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _read(TextEditingController controller, [double? original]) {
    if (controller.text == _display(original)) return original;
    final text = controller.text.trim().replaceAll(',', '.');
    return text.isEmpty ? null : parseNumber(text);
  }

  String? _validateNumber(
    String? value, {
    required AppLocalizations strings,
    double? maximum,
  }) {
    final text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) return null;
    final parsed = parseNumber(text);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < 0 ||
        (maximum != null && parsed > maximum)) {
      return strings.invalidNumber;
    }
    return null;
  }

  Future<void> _save() async {
    final strings = AppLocalizations.of(context)!;
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final profileName = name.text.trim();
      final ghValue = _read(gh, _seed?.ghPpmAsCaCO3);
      final khValue = _read(kh, _seed?.khPpmAsCaCO3);
      final tdsValue = _read(tds, _seed?.tdsPpm);
      final phValue = _read(ph, _seed?.ph);
      final minerals = _minerals;
      final existing = widget.existing;
      final id = existing == null
          ? await widget.repository.createWaterProfile(
              name: profileName,
              ghPpmAsCaCO3: ghValue,
              khPpmAsCaCO3: khValue,
              tdsPpm: tdsValue,
              ph: phValue,
              minerals: minerals,
              notes: notes.text,
              recipeJson: _recipeJson,
            )
          : existing.id;
      if (existing != null) {
        await widget.repository.updateWaterProfile(
          id: existing.id,
          name: profileName,
          ghPpmAsCaCO3: ghValue,
          khPpmAsCaCO3: khValue,
          tdsPpm: tdsValue,
          ph: phValue,
          minerals: minerals,
          notes: notes.text,
          recipeJson: _recipeJson,
        );
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        WaterProfile(
          id: id,
          name: profileName,
          ghPpmAsCaCO3: ghValue,
          khPpmAsCaCO3: khValue,
          tdsPpm: tdsValue,
          ph: phValue,
          calciumPpm: minerals.calcium,
          magnesiumPpm: minerals.magnesium,
          sodiumPpm: minerals.sodium,
          potassiumPpm: minerals.potassium,
          chloridePpm: minerals.chloride,
          sulfatePpm: minerals.sulfate,
          bicarbonatePpm: minerals.bicarbonate,
          recipeJson: _recipeJson,
          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          archivedAtMs: existing?.archivedAtMs,
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        showOperationError(context, error, strings.saveFailed);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String? get _recipeJson {
    final source = _seed?.recipeJson;
    if (source == null) return null;
    try {
      final expected = WaterRecipe.fromJson(source).result;
      final minerals = _minerals;
      final edited = WaterComposition(
        measuredGh: _read(gh, _seed?.ghPpmAsCaCO3),
        measuredKh: _read(kh, _seed?.khPpmAsCaCO3),
        ions: {
          WaterIon.calcium: minerals.calcium,
          WaterIon.magnesium: minerals.magnesium,
          WaterIon.sodium: minerals.sodium,
          WaterIon.potassium: minerals.potassium,
          WaterIon.chloride: minerals.chloride,
          WaterIon.sulfate: minerals.sulfate,
          WaterIon.bicarbonate: minerals.bicarbonate,
        },
      );
      bool same(double? left, double? right) {
        if (left == null || right == null) return left == right;
        return (left - right).abs() <= 1e-6;
      }

      if (!same(edited.gh, expected.gh) || !same(edited.kh, expected.kh)) {
        return null;
      }
      for (final ion in WaterIon.values) {
        if (!same(edited[ion], expected[ion])) return null;
      }
      return source;
    } on FormatException {
      return null;
    }
  }

  /// The minerals, two by row, open when any is filled in.
  Widget _mineralFields(AppLocalizations strings) => ExpansionTile(
    key: const ValueKey('water-minerals'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    initiallyExpanded: [
      calcium,
      magnesium,
      sodium,
      potassium,
      chloride,
      sulfate,
      bicarbonate,
    ].any((field) => field.text.trim().isNotEmpty),
    title: Text(strings.waterMinerals),
    subtitle: Text(strings.mineralsHint),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _waterNumberField(
          controller: bicarbonate,
          label: strings.waterBicarbonate,
          strings: strings,
        ),
      ),
      for (final (left, right) in [
        ((calcium, strings.calcium), (magnesium, strings.magnesium)),
        ((sodium, strings.sodium), (potassium, strings.potassium)),
        ((chloride, strings.chloride), (sulfate, strings.sulfate)),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _waterNumberField(
                  controller: left.$1,
                  label: left.$2,
                  strings: strings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _waterNumberField(
                  controller: right.$1,
                  label: right.$2,
                  strings: strings,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height - keyboard - 24;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.existing == null
                          ? strings.addWaterProfile
                          : strings.editWaterProfile,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    children: [
                      TextFormField(
                        controller: name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: strings.waterProfileName,
                          contentPadding: const EdgeInsets.fromLTRB(
                            14,
                            24,
                            14,
                            18,
                          ),
                        ),
                        validator: (value) => value?.trim().isEmpty != false
                            ? strings.requiredField
                            : null,
                      ),
                      if (_seed?.recipeJson != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(strings.waterRecipeEditHint),
                        ),
                      const SizedBox(height: 12),
                      _waterNumberField(
                        controller: gh,
                        label: strings.waterHardness,
                        strings: strings,
                      ),
                      const SizedBox(height: 12),
                      _waterNumberField(
                        controller: kh,
                        label: strings.waterAlkalinity,
                        strings: strings,
                      ),
                      const SizedBox(height: 12),
                      _waterNumberField(
                        controller: tds,
                        label: strings.waterTdsPpm,
                        strings: strings,
                      ),
                      const SizedBox(height: 12),
                      _waterNumberField(
                        controller: ph,
                        label: strings.waterPh,
                        strings: strings,
                        maximum: 14,
                      ),
                      const SizedBox(height: 4),
                      _mineralFields(strings),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notes,
                        maxLines: 3,
                        minLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: strings.waterProfileNotes,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          child: Text(strings.cancel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving ? null : _save,
                          child: Text(strings.save),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waterNumberField({
    required TextEditingController controller,
    required String label,
    required AppLocalizations strings,
    double? maximum,
  }) => TextFormField(
    controller: controller,
    inputFormatters: [decimalInputFormatter],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
    ),
    validator: (value) =>
        _validateNumber(value, strings: strings, maximum: maximum),
  );
}
