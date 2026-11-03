import 'package:flutter/material.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/water_profile_values.dart';
import 'package:intl/intl.dart';

const waterDisplayIons = [
  WaterIon.calcium,
  WaterIon.magnesium,
  WaterIon.potassium,
  WaterIon.sodium,
  WaterIon.sulfate,
  WaterIon.chloride,
];

class WaterCompositionInputs extends StatelessWidget {
  const WaterCompositionInputs({
    super.key,
    required this.ions,
    required this.kh,
    required this.prefix,
    this.gh,
    this.target = false,
  });
  final Map<WaterIon, TextEditingController> ions;
  final TextEditingController kh;
  final TextEditingController? gh;
  final String prefix;
  final bool target;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    Widget ionField(WaterIon ion, {bool optional = true}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: waterInput(
        ions[ion]!,
        '${ionLabel(s, ion)} (${ionSymbol(ion)}, mg/L)',
        s,
        key: '$prefix-${ion.name}',
        optional: optional,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        waterInput(
          kh,
          s.waterAlkalinity,
          s,
          key: '$prefix-kh',
          optional: !target,
        ),
        const SizedBox(height: 12),
        ionField(WaterIon.calcium, optional: !target),
        ionField(WaterIon.magnesium, optional: !target),
        ExpansionTile(
          key: ValueKey('$prefix-more-ions'),
          tilePadding: EdgeInsets.zero,
          title: Text(s.waterOtherIons),
          subtitle: Text(target ? s.waterOptionalTargets : s.waterUnknownHint),
          children: [
            for (final ion in waterDisplayIons.skip(2)) ionField(ion),
            if (!target) ...[
              ionField(WaterIon.bicarbonate),
              if (gh != null)
                waterInput(
                  gh!,
                  s.waterManualGh,
                  s,
                  key: '$prefix-gh',
                  helperText: s.waterManualGhHint,
                  optional: true,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class WaterDerivedValues extends StatelessWidget {
  const WaterDerivedValues({super.key, required this.water});
  final WaterComposition water;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final number = NumberFormat('0.##', regionalLocale.toString());
    final gh = water.calculatedGh;
    final ratio = water.calciumMagnesiumMassRatio;
    return Text(
      '${s.waterDerivedGh}: ${gh == null ? '—' : number.format(gh)}\n'
      '${s.waterMassRatio}: ${ratio == null ? '—' : '${number.format(ratio)}:1'}',
    );
  }
}

Widget waterInput(
  TextEditingController controller,
  String label,
  AppLocalizations s, {
  String? key,
  bool optional = false,
  bool positive = false,
  double? maximum,
  String? helperText,
}) => TextFormField(
  key: key == null ? null : ValueKey(key),
  controller: controller,
  inputFormatters: [decimalInputFormatter],
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  autovalidateMode: AutovalidateMode.onUserInteraction,
  decoration: InputDecoration(
    labelText: label,
    helperText: helperText,
    helperMaxLines: 8,
  ),
  validator: (value) {
    final text = value?.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) return optional ? null : s.requiredField;
    final number = parseNumber(text);
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        (positive && number == 0) ||
        (maximum != null && number > maximum)) {
      return s.invalidNumber;
    }
    return null;
  },
);
