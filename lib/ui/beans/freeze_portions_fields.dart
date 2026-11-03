import 'package:flutter/material.dart';
import 'package:holybeans/domain/freeze_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class FreezePortionsFields extends StatelessWidget {
  const FreezePortionsFields({
    super.key,
    required this.split,
    required this.portionGrams,
    required this.plan,
    required this.includeRemainder,
    required this.onSplit,
    required this.onRemainder,
  });

  final bool split;
  final TextEditingController portionGrams;
  final FreezePlan? plan;
  final bool includeRemainder;
  final ValueChanged<bool> onSplit;
  final ValueChanged<bool> onRemainder;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final division = plan;
    String grams(double value) => formatGrams(value, regionalLocale.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('freeze-split'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.freezeSplit),
          value: split,
          onChanged: onSplit,
        ),
        if (split) ...[
          TextFormField(
            key: const ValueKey('freeze-portion-grams'),
            controller: portionGrams,
            inputFormatters: [decimalInputFormatter],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s.freezePortionGrams),
            validator: (_) => plan == null ? s.freezeInvalidDivision : null,
          ),
          if (division != null) ...[
            const SizedBox(height: 8),
            Text(s.freezeDivision(division.count, grams(division.grams))),
            if (division.remainder > 0)
              CheckboxListTile(
                key: const ValueKey('freeze-remainder'),
                contentPadding: EdgeInsets.zero,
                value: includeRemainder,
                onChanged: (value) => onRemainder(value!),
                title: Text(s.freezeRemainder(grams(division.remainder))),
                subtitle: Text(s.freezeRemainderHint),
              ),
          ],
        ],
      ],
    );
  }
}
